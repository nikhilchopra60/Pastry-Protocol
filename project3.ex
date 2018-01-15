defmodule Project3 do
  use GenServer
 
  def main(args) do
    if (Enum.count(args)!=2) do
      IO.puts" Illegal Arguments Provided"
      System.halt(1)
    else
        numNodes=Enum.at(args, 0)|>String.to_integer()
        numRequests=Enum.at(args, 1)|>String.to_integer()
        
        initiatePastryProtocol(numNodes,numRequests)
        infiniteLoop()
    end
  end 

  def infiniteLoop() do
    infiniteLoop()
  end

  def initiatePastryProtocol(numNodes,numRequests) do
    tableRows= :math.ceil( :math.log(numNodes) / :math.log(4) )  ##in ets
    tableRows= round(tableRows)
    nodeIDSpace =round(:math.pow(4,tableRows))   ##in ets
    cryptoHashes=[]
    initialPhase=[]
    numInitialPhase=0
    if(numNodes<=1024) do
      numInitialPhase=numNodes
    else
      numInitialPhase=1024
    end

    numberOfNodesJoined=0     ##in ets
    numNotinBothPhases=0  ##in ets
    numRouted=0 ##in ets
    numHops=0   ##in ets
    numRouteNotinBothPhases=0 
       
    etsTable = :ets.new(:etsTable, [:named_table,:public])
    
    :ets.insert(:etsTable, {"tableRows",tableRows})
    :ets.insert(:etsTable, {"numNodes",numNodes})
    :ets.insert(:etsTable, {"numRequests",numRequests})
    :ets.insert(:etsTable, {"nodeIDSpace",nodeIDSpace})
    :ets.insert(:etsTable, {"numInitialPhase",numInitialPhase})
    

    cryptoHashes = Enum.map(0..nodeIDSpace - 1, fn(x) -> x end)
    cryptoHashes = Enum.shuffle(cryptoHashes)
    :ets.insert(:etsTable, {"cryptoHashes",cryptoHashes})
 
	{initialPhase,remainingGrp} = Enum.split(cryptoHashes,numInitialPhase-1)
     
    pidMain=start_Main_node(numberOfNodesJoined,numNotinBothPhases,numRouted,numHops,numRouteNotinBothPhases)
    
    Enum.each(0..numNodes - 1, fn(x) ->   
    ##start genserver for each node TODO send node id along
      start_Pastry_Protocol(Enum.fetch!(cryptoHashes,x))
    end)


    GenServer.cast(:master, {:StartPastry,initialPhase})
    
  end
 

  def handle_cast({:StartPastry,initialPhase},state) do
    
    [{_, numInitialPhase}]=:ets.lookup(:etsTable, "numInitialPhase")
    [{_, cryptoHashes}]=:ets.lookup(:etsTable, "cryptoHashes")
    
    Enum.each(0..numInitialPhase - 1, fn(x) -> 
      id=Enum.fetch!(cryptoHashes,x)
      nameAtom= id |>Integer.to_string|>String.to_atom
      GenServer.cast(nameAtom, {:FirstPhase,initialPhase})
    end)
    {:noreply,state}
  end

  def handle_cast({:FirstPhase, initialPhase},state) do 
    [{_, tableRows}]=:ets.lookup(:etsTable, "tableRows")
    {myID,smallerLeaf,largerLeaf, table, numOfBack}=state
    initialPhase= List.delete(initialPhase,myID)
   
    newState=addNodeList(initialPhase,state,tableRows)
    state=newState
    {myID,smallerLeaf,largerLeaf, table, numOfBack}=state
    
    val=convertToBase4String(myID, tableRows)
    table=updateFirstPhaseTable(val,table,0,myID,tableRows)
    #IO.puts "table updates after add buffer #{myID}"

    state={myID,smallerLeaf,largerLeaf, table, numOfBack}
    GenServer.cast(:master,{:DistributedHashTablesFormed})
    {:noreply, state} 
  end

  def updateFirstPhaseTable(val,table,i,myID,tableRows) when i==tableRows do
    table
  end 

  def updateFirstPhaseTable(val,table,i,myID,tableRows) do
    col=val|>String.at(i)|>String.to_integer
    table= put_in(table[i][col], myID)
    updateFirstPhaseTable(val,table,i + 1,myID, tableRows)
  end
  
  
  def handle_cast({:DistributedHashTablesFormed},state) do
    [{_, numInitialPhase}]=:ets.lookup(:etsTable, "numInitialPhase")
    [{_, numNodes}]=:ets.lookup(:etsTable, "numNodes")
    {numberOfNodesJoined,numNotinBothPhases,numRouted,numHops,numRouteNotinBothPhases}=state
    numberOfNodesJoined= numberOfNodesJoined + 1
    if(numberOfNodesJoined == numInitialPhase) do
      if(numberOfNodesJoined >= numNodes) do
          GenServer.cast(:master,{:BeginRouteMaster})
      else
        GenServer.cast(:master,{:SecondPhase})
      end
    end
    if(numberOfNodesJoined > numInitialPhase) do
      if(numberOfNodesJoined == numNodes) do
        #BEGINROUTE
        GenServer.cast(:master,{:BeginRouteMaster})
      else
        #SencondPhase
        GenServer.cast(:master,{:SecondPhase})
      end
    end
    state={numberOfNodesJoined,numNotinBothPhases,numRouted,numHops,numRouteNotinBothPhases}
    {:noreply,state}
  end

  def handle_cast({:BeginRouteMaster},state) do
 
    {numberOfNodesJoined,numNotinBothPhases,numRouted,numHops,numRouteNotinBothPhases}=state
    [{_, cryptoHashes}]=:ets.lookup(:etsTable, "cryptoHashes")
    [{_, numNodes}]=:ets.lookup(:etsTable, "numNodes")
    Enum.each(0..numNodes-1, fn(x) -> 
      nodeID = Enum.fetch!(cryptoHashes,x)
      nameAtom= nodeID |>Integer.to_string|>String.to_atom
      GenServer.cast(nameAtom,{:StartRouteMsg})
     end)
    {:noreply,state}
  end

  def handle_cast({:StartRouteMsg},state) do
    {myID,smallerLeaf,largerLeaf, table, numOfBack}=state
    [{_, numRequests}]=:ets.lookup(:etsTable, "numRequests")
    [{_, nodeIDSpace}]=:ets.lookup(:etsTable, "nodeIDSpace")
    [{_, tableRows}]=:ets.lookup(:etsTable, "tableRows")
    Enum.each(1..numRequests, fn(x) -> 
      random_number = :rand.uniform(nodeIDSpace - 1)
      nameAtom= myID |>Integer.to_string|>String.to_atom
      GenServer.cast(nameAtom,{:SendMsg,myID, random_number, -1, tableRows, nodeIDSpace})
      :timer.sleep(10)
    end)

    {:noreply,state}
  end

  def handle_cast({:SendMsg,fromID, destinationID, hops, tableRows, nodeIDSpace},state) do
    {myID,smallerLeaf,largerLeaf, table, numOfBack}=state

    if myID == destinationID do
      GenServer.cast(:master,{:MessageReceivedAtDestination,fromID,destinationID, hops + 1})
    else
      shl= commonPrefixLength(convertToBase4String(myID,tableRows),convertToBase4String(destinationID, tableRows))
      cond do
        ((length(smallerLeaf) > 0 && destinationID >= Enum.min(smallerLeaf) && destinationID < myID) || (length(largerLeaf) > 0 && destinationID <= Enum.max(largerLeaf) && destinationID > myID)) ->
          diff=nodeIDSpace + 10
          nearest= - 1
          if(destinationID < myID) do
            {nearest, diff}= updateNearestAndDiff(smallerLeaf, 0, destinationID, diff, nearest)
          else 
            {nearest, diff}= updateNearestAndDiff(largerLeaf, 0, destinationID, diff, nearest)
          end
    
          if (abs(destinationID - myID) > diff) do
            nameAtom= nearest |>Integer.to_string|>String.to_atom
            GenServer.cast(nameAtom,{:SendMsg,fromID,destinationID,hops + 1, tableRows, nodeIDSpace})
          else
            GenServer.cast(:master,{:MessageReceivedAtDestination,fromID,destinationID, hops + 1})
          end

        (length(smallerLeaf) < 4 && length(smallerLeaf) > 0 && destinationID < Enum.min(smallerLeaf)) ->
            nameAtom= Enum.min(smallerLeaf) |>Integer.to_string|>String.to_atom
            GenServer.cast(nameAtom,{:SendMsg,fromID,destinationID,hops + 1, tableRows, nodeIDSpace})
  
        (length(largerLeaf) < 4 && length(largerLeaf) > 0 && destinationID > Enum.max(largerLeaf))->
            nameAtom= Enum.max(largerLeaf) |>Integer.to_string|>String.to_atom
            GenServer.cast(nameAtom,{:SendMsg,fromID,destinationID,hops + 1, tableRows, nodeIDSpace})
  
        ((length(smallerLeaf) == 0 && destinationID < myID) || (length(largerLeaf) == 0 && destinationID > myID)) ->
            GenServer.cast(:master,{:MessageReceivedAtDestination,fromID, destinationID, hops + 1})
  
        (table[shl][convertToBase4String(destinationID, tableRows)|>String.at(shl)|>String.to_integer] != -1) ->
            col=convertToBase4String(destinationID, tableRows)|>String.at(shl)|>String.to_integer
            nameAtom= table[shl][col]|>Integer.to_string|>String.to_atom
            GenServer.cast(nameAtom,{:SendMsg,fromID,destinationID,hops + 1, tableRows, nodeIDSpace})
          
        (destinationID > myID) ->
            nameAtom= Enum.max(largerLeaf) |>Integer.to_string|>String.to_atom
            GenServer.cast(nameAtom,{:SendMsg,fromID,destinationID,hops + 1, tableRows, nodeIDSpace})
            GenServer.cast(:master,{:RouteNotinBothPhases})
  
        (destinationID < myID)->
            nameAtom= Enum.min(smallerLeaf) |>Integer.to_string|>String.to_atom
            GenServer.cast(nameAtom,{:SendMsg,fromID,destinationID,hops + 1, tableRows, nodeIDSpace})
            GenServer.cast(:master,{:RouteNotinBothPhases})
  
        true-> 
            true 
      end
    end
    {:noreply,state}
  end

  def handle_cast({:RouteNotinBothPhases},state) do
    {numberOfNodesJoined,numNotinBothPhases,numRouted,numHops,numRouteNotinBothPhases} = state
    state = {numberOfNodesJoined,numNotinBothPhases,numRouted,numHops,numRouteNotinBothPhases + 1}
    {:noreply, state}
  end

  def handle_cast({:NotinBothPhases},state) do
    {numberOfNodesJoined,numNotinBothPhases,numRouted,numHops,numRouteNotinBothPhases} = state
    state = {numberOfNodesJoined,numNotinBothPhases + 1,numRouted,numHops,numRouteNotinBothPhases}
    {:noreply, state}
  end

  def handle_cast({:MessageReceivedAtDestination,fromID,destinationID,hops},state) do
    #IO.puts "Inside route finish from = #{fromID}"
    {numberOfNodesJoined,numNotinBothPhases,numRouted,numHops,numRouteNotinBothPhases}=state
    [{_, numRequests}]=:ets.lookup(:etsTable, "numRequests")
    [{_, numNodes}]=:ets.lookup(:etsTable, "numNodes")
    numRouted=numRouted + 1
    numHops = numHops + hops 

    if(numRouted >=numNodes * numRequests) do
      IO.puts "Number of Total Routes = #{numRouted}"
      IO.puts "Number of Total Hops = #{numHops}"
      ratio = numHops / numRouted
      IO.puts "Average Hops per route = #{ratio}"
      #######exit the system and stop
      System.halt(1)
    end
    state = {numberOfNodesJoined,numNotinBothPhases,numRouted,numHops,numRouteNotinBothPhases}
    {:noreply, state}
  end

  def handle_cast({:SecondPhase},state) do
    {numberOfNodesJoined,numNotinBothPhases,numRouted,numHops,numRouteNotinBothPhases}=state
    [{_, cryptoHashes}]=:ets.lookup(:etsTable, "cryptoHashes")
    chosenRandomIndex= :rand.uniform(numberOfNodesJoined - 1)
    startID=Enum.fetch!(cryptoHashes,chosenRandomIndex)
    destID=Enum.fetch!(cryptoHashes,numberOfNodesJoined)

    nameAtom= startID |>Integer.to_string|>String.to_atom
    GenServer.cast(nameAtom,{:RouteJoin,startID,destID,-1})
    {:noreply,state}
  end

  def handle_cast({:RouteJoin,fromID, destinationID, hops},state) do
    {myID,smallerLeaf,largerLeaf, table, numOfBack}=state
    [{_, tableRows}]=:ets.lookup(:etsTable, "tableRows")
	[{_, nodeIDSpace}]=:ets.lookup(:etsTable, "nodeIDSpace")
    shl= commonPrefixLength(convertToBase4String(myID,tableRows),convertToBase4String(destinationID,tableRows))
    
    if(hops== -1 && shl >0) do
      Enum.each(0..shl - 1,fn(i)-> 
        nameAtom= destinationID |>Integer.to_string|>String.to_atom
        tableRow=Enum.map(0..3, fn(x) -> table[i][x] end)  # TO BE TESTEDDDDDDDDDDDdd
        GenServer.call(nameAtom,{:UpdateDistributedTableRow,i,tableRow})
      end)
    end
    
    nameAtom= destinationID |>Integer.to_string|>String.to_atom
    tableRow=Enum.map(0..3, fn(x) -> table[shl][x] end)
    GenServer.call(nameAtom,{:UpdateDistributedTableRow,shl,tableRow})

    cond do
      ((length(smallerLeaf) > 0 && destinationID >= Enum.min(smallerLeaf) && destinationID <= myID) || (length(largerLeaf) > 0 && destinationID <= Enum.max(largerLeaf) && destinationID >= myID)) ->

        diff = nodeIDSpace + 10
        nearest = -1
        if(destinationID < myID) do
         {nearest, diff}= updateNearestAndDiff(smallerLeaf, 0, destinationID, diff, nearest)
        else 
         {nearest, diff}= updateNearestAndDiff(largerLeaf, 0, destinationID, diff, nearest)
        end
  
        if (abs(destinationID - myID) > diff) do
          nameAtom= nearest |>Integer.to_string|>String.to_atom
          GenServer.cast(nameAtom,{:RouteJoin,fromID,destinationID,hops+1})
        else
          allLeaf=[myID] ++ smallerLeaf ++ largerLeaf      # CHECK THISSSSSSSSSSSSSS
          nameAtom= destinationID |>Integer.to_string|>String.to_atom
          GenServer.cast(nameAtom,{:AddLeafToLeafSet,allLeaf})
        end

      (length(smallerLeaf) < 4 && length(smallerLeaf) > 0 && destinationID < Enum.min(smallerLeaf)) ->
          nameAtom= Enum.min(smallerLeaf) |>Integer.to_string|>String.to_atom
          GenServer.cast(nameAtom,{:RouteJoin,fromID,destinationID,hops + 1})

      (length(largerLeaf) < 4 && length(largerLeaf) > 0 && destinationID > Enum.max(largerLeaf))->
          nameAtom= Enum.max(largerLeaf) |>Integer.to_string|>String.to_atom
          GenServer.cast(nameAtom,{:RouteJoin,fromID,destinationID,hops + 1})

      ((length(smallerLeaf) == 0 && destinationID < myID) || (length(largerLeaf) == 0 && destinationID > myID)) ->
          allLeaf=[myID] ++ smallerLeaf ++ largerLeaf
          nameAtom= destinationID |>Integer.to_string|>String.to_atom
          GenServer.cast(nameAtom,{:AddLeafToLeafSet,allLeaf})

      (table[shl][convertToBase4String(destinationID, tableRows)|>String.at(shl)|>String.to_integer] != -1) ->
          col=convertToBase4String(destinationID, tableRows)|>String.at(shl)|>String.to_integer
          nameAtom= table[shl][col] |> Integer.to_string|>String.to_atom
          GenServer.cast(nameAtom,{:RouteJoin,fromID,destinationID,hops + 1})
        
      (destinationID > myID) ->
          nameAtom= Enum.max(largerLeaf) |>Integer.to_string|>String.to_atom
          GenServer.cast(nameAtom,{:RouteJoin,fromID,destinationID,hops + 1})
          GenServer.cast(:master,{:NotinBothPhases})

      (destinationID < myID)->
          nameAtom= Enum.min(smallerLeaf) |>Integer.to_string|>String.to_atom
          GenServer.cast(nameAtom,{:RouteJoin,fromID,destinationID,hops + 1})
          GenServer.cast(:master,{:NotinBothPhases})

      true-> 
          true 
    end
    {:noreply,state}
  end

  def updateNearestAndDiff(list, counter, destinationID, diff, nearest) when counter == length(list) do
    {nearest,diff}
  end

  def updateNearestAndDiff(list, counter, destinationID, diff, nearest) do
    val = Enum.fetch!(list,counter)
    if(abs(destinationID-val) < diff) do
      nearest=val
      diff = abs(destinationID-val)
    end
    updateNearestAndDiff(list,counter + 1, destinationID, diff, nearest)
  end

  def updateTable(table, newRow,rowNum,x) when x==4 do
    table
  end
  def updateTable(table, newRow,rowNum,x) do
      if(table[rowNum][x] == -1) do
        newVal=Enum.fetch!(newRow,x)
        table=put_in(table[rowNum][x], newVal)
      end   
      updateTable(table,newRow,rowNum,x+1)
  end
    
  def handle_call({:UpdateDistributedTableRow,rowNum, newRow},_from,state) do
    {myID,smallerLeaf,largerLeaf, table, numOfBack}=state
    table = updateTable(table, newRow,rowNum,0)
    state= {myID,smallerLeaf,largerLeaf, table, numOfBack}
    {:reply,myID,state}
  end

  def handle_cast({:AddLeafToLeafSet,allLeaf},state) do
    {myID,smallerLeaf,largerLeaf, table, numOfBack}=state
    [{_, tableRows}]=:ets.lookup(:etsTable, "tableRows")
    newState=addNodeList(allLeaf,state, tableRows)
    state=newState
    {myID,smallerLeaf,largerLeaf, table, numOfBack}=state
    Enum.each(smallerLeaf,fn(x)-> 
      nameAtom= x |>Integer.to_string|>String.to_atom
      GenServer.cast(nameAtom,{:UpdateStateSelf,myID})
    end)
    numOfBack = numOfBack + length(smallerLeaf)

    Enum.each(largerLeaf,fn(x)-> 
      nameAtom= x |>Integer.to_string|>String.to_atom
      GenServer.cast(nameAtom,{:UpdateStateSelf,myID})
    end)
    numOfBack = numOfBack + length(largerLeaf)
   
    numOfBack = updateNumOfBackAddLeaf(numOfBack, table, 0, myID, tableRows)
   
    val=convertToBase4String(myID, tableRows)
    table=updateFirstPhaseTable(val,table,0,myID,tableRows)

    state={myID,smallerLeaf,largerLeaf, table, numOfBack}
    {:noreply,state}
  end

  def updateNumOfBackAddLeaf(numofBack,table,i, myID, tableRows) when i==tableRows  do
    numofBack
  end

  def updateNumOfBackAddLeaf(numofBack,table,i, myID, tableRows) do
    j=0
    if(table[i][0] != -1) do
      numofBack = numofBack + 1
      nameAtom= table[i][0] |>Integer.to_string|>String.to_atom
      GenServer.cast(nameAtom,{:UpdateStateSelf,myID})
    end
    if(table[i][1] != -1) do
      numofBack = numofBack + 1
      nameAtom= table[i][1] |>Integer.to_string|>String.to_atom
      GenServer.cast(nameAtom,{:UpdateStateSelf,myID})
    end
    if(table[i][2] != -1) do
      numofBack = numofBack + 1
      nameAtom= table[i][2] |>Integer.to_string|>String.to_atom
      GenServer.cast(nameAtom,{:UpdateStateSelf,myID})
    end
    if(table[i][3] != -1) do
      numofBack = numofBack + 1
      nameAtom= table[i][3] |>Integer.to_string|>String.to_atom
      GenServer.cast(nameAtom,{:UpdateStateSelf,myID})
    end
    updateNumOfBackAddLeaf(numofBack,table, i+1, myID, tableRows)
  end

  def handle_cast({:UpdateStateSelf,nodeID},state) do
    {myID,smallerLeaf,largerLeaf, table, numOfBack}=state
    
    state=addNode(nodeID,state)
    nameAtom= nodeID|>Integer.to_string|>String.to_atom
    GenServer.cast(nameAtom,{:SendAckToSender})
    state={myID,smallerLeaf,largerLeaf, table, numOfBack}
    {:noreply,state}
  end

  def handle_cast({:SendAckToSender},state) do
    {myID,smallerLeaf,largerLeaf, table, numOfBack}=state
    numOfBack=numOfBack-1
    if(numOfBack==0) do
      GenServer.cast(:master,{:DistributedHashTablesFormed})
    end
    state={myID,smallerLeaf,largerLeaf, table, numOfBack}
    {:noreply,state}
  end

   def start_Pastry_Protocol(myID) do
    [{_, tableRows}]=:ets.lookup(:etsTable, "tableRows")
    nameAtom=myID|>Integer.to_string|>String.to_atom
    table= Enum.map(0..tableRows - 1,fn(x)-> 
      [-1,-1,-1,-1]
    end)
    table=Matrix.from_list(table)
    {:ok,pid}=GenServer.start_link(__MODULE__,{myID,[],[],table, 0} , name: nameAtom)
                                              #{myID,smallerLeaf,largerLeaf, table, numOfBack}
    pid
  end

  def start_Main_node(tableRows,remainingGrp,numInitialPhase,numNodes,numRequests) do
    {:ok,pid}=GenServer.start_link(__MODULE__,{0,0,0,0,0}, name: :master)
  end                         #{numberOfNodesJoined,numNotinBothPhases,numRouted,numHops,numRouteNotinBothPhases}

  def convertToBase4String(input,length) do 
    str=Integer.to_string(input,4)
    initial = str
    diff=length-String.length(str)
    if(diff>0) do
     str =  String.pad_leading(str,length,"0")
    end
    str
  end

  def commonPrefixLength(str1,str2) do ## check this individually
    count=0
    #minLength= max(String.length(str1) , String.length(str2))
    minLength= String.length(str1)
    lengthOfCommon(str1,str2,minLength,count)
  end

  def lengthOfCommon(str1,str2,minLength,count) do
    if(count <= minLength - 1) do
      if( String.at(str1,count) ==   String.at(str2,count)  ) do
        lengthOfCommon(str1,str2,minLength,count+1)  
      else
        count
      end
    else
      count
    end   
  end

  def recurseAddNodeList(allList,x,state, tableRows) when x==length(allList) do
    state
  end

  def recurseAddNodeList(allList,x,state, tableRows) do
    
      {myID,smallerLeaf,largerLeaf, table, numOfBack}=state
      value=Enum.fetch!(allList,x)
      cond do
        
        (value > myID && Enum.member?(largerLeaf,value)==false)->  
          if(length(largerLeaf)< 4) do
            largerLeaf= largerLeaf ++ [value]
          else
            if(value < Enum.max(largerLeaf)) do
              largerLeaf = largerLeaf -- [Enum.max(largerLeaf)]
              largerLeaf= largerLeaf ++ [value]
            end
          end
      
        (value < myID && Enum.member?(smallerLeaf,value)==false)->  
            if(length(smallerLeaf)< 4) do
              smallerLeaf= smallerLeaf ++ [value]
            else
              if(value > Enum.min(smallerLeaf)) do
                smallerLeaf = smallerLeaf -- [Enum.min(smallerLeaf)]
                smallerLeaf= smallerLeaf ++ [value]
              end
            end
        true->true
      end 
	  
      shl= commonPrefixLength(convertToBase4String(myID,tableRows),convertToBase4String(value,tableRows))
      val = convertToBase4String(value, tableRows)|>String.at(shl) 
      
	  if(table[shl][convertToBase4String(value, tableRows)|>String.at(shl)|>String.to_integer] == -1) do
        col=convertToBase4String(value, tableRows) |>String.at(shl)|>String.to_integer
        table = put_in(table[shl][col], value) 
      end
      state={myID,smallerLeaf,largerLeaf, table, numOfBack}
      recurseAddNodeList(allList,x + 1,state,tableRows)    
  end

  def addNodeList(allList,state, tableRows) do 
    state=recurseAddNodeList(allList,0,state, tableRows)
    state
  end

  def addNode(nodeID,state) do
      {myID,smallerLeaf,largerLeaf, table, numOfBack}=state
      [{_, tableRows}]=:ets.lookup(:etsTable, "tableRows")
    
      cond do
        (nodeID > myID && Enum.member?(largerLeaf,nodeID)==false)->
          if(length(largerLeaf)< 4) do
            largerLeaf= largerLeaf ++ [nodeID]
          else
            if(nodeID < Enum.max(largerLeaf)) do
              largerLeaf = largerLeaf -- [Enum.max(largerLeaf)]
              largerLeaf= largerLeaf ++ [nodeID]
            end
          end
         
        (nodeID < myID && Enum.member?(smallerLeaf,nodeID)==false)->  
            if(length(smallerLeaf)< 4) do
              smallerLeaf= smallerLeaf ++ [nodeID]
            else
              if(nodeID > Enum.min(smallerLeaf)) do
                smallerLeaf = smallerLeaf -- [Enum.min(smallerLeaf)]
                smallerLeaf= smallerLeaf ++ [nodeID]
              end
            end
        true->true
      end 

      shl= commonPrefixLength(convertToBase4String(myID,tableRows),convertToBase4String(nodeID,tableRows))
      if(table[shl][convertToBase4String(nodeID, tableRows)|>String.at(shl)|>String.to_integer] == -1) do
         col=convertToBase4String(nodeID, tableRows)|>String.at(shl)|>String.to_integer

         table = put_in(table[shl][col], nodeID)
      end
    
      state={myID,smallerLeaf,largerLeaf, table, numOfBack}
      state
  end

end
