Macro "Open Transit HH Strata Coverage Dbox" (Args)
	RunDbox("Transit HH Strata Coverage", Args)
endmacro

dBox "Transit HH Strata Coverage" (Args) location: center, center, 80, 20
  Title: "Transit HH Strata Coverage" toolbox NoKeyBoard

  // What happens when the "x" is clicked
  close do
    return()
  enditem

  // Quit Button
  button 5, 18, 10 Prompt:"Quit" do
    Return(1)
  enditem

  init do
    
    static Radius_list, StopRadius_Index, StopBuffer, RouteRadius_Index, RouteBuffer
    static TOD, TOD_list, TOD_Index, UseStop, UseRoute

    Radius_list = {"0.1","0.25","0.5","0.75","1","1.5","2","2.5","3"}
    TOD_list = {"Daily","AM", "MD", "PM", "NT"}

    EnableItem("Select Stop Buffer Radius")
	EnableItem("Select Route Buffer Radius")

  enditem

  // Select Radius
  Popdown Menu "Select Stop Buffer Radius" 35,1,10,5 Prompt: "Choose Stop Buffer Radius (Miles)" 
    List: Radius_list Variable: StopRadius_Index do
    StopBuffer = Radius_list[StopRadius_Index]
  enditem

  Popdown Menu "Select Route Buffer Radius" 36,3,10,5 Prompt: "Choose Route Buffer Radius (Miles)" 
    List: Radius_list Variable: RouteRadius_Index do
    RouteBuffer = Radius_list[RouteRadius_Index]
  enditem
  
  text 5, 12 variable: "Select Which to use"   
  checkbox 25, 12 prompt: "Use Stop Buffer" Variable: UseStop 
  checkbox 45, 12 prompt: "Use Route Buffer" Variable: UseRoute
  
  // Select TOD
  Popdown Menu "Select TOD" 17,14,10,5 Prompt: "Choose TOD" 
    List: TOD_list Variable: TOD_Index do
    TOD = TOD_list[TOD_Index]
  enditem
  
  // Make Map Button
  button 40, 18, 30 Prompt:"Generate Transit Coverage" do 
    if UseStop = 1 and (StopBuffer = null or TOD = null) then ShowMessage("Please make a selection for all drop down lists.")
    else if UseStop = 1 then RunMacro("HH_Strata_Estimator_Stop", Args, TOD, StopBuffer) 
		
    if UseRoute = 1 and (RouteBuffer = null or TOD = null) then ShowMessage("Please make a selection for all drop down lists.")
    else if UseRoute = 1 then RunMacro("HH_Strata_Estimator_Route",  Args, TOD, RouteBuffer)

    ShowMessage("Reports have been created successfully.")
  Enditem

enddbox

//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                        Macro "HH_Strata_Estimator_Route"
//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Macro "HH_Strata_Estimator_Route" (Args, TOD, RouteBuffer)

  // Set directory and create output folder
  Scenario_Dir = Args.[Scenario Folder]
  TransModeTable = Args.TransModeTable
  taz_file = Args.TAZs
  hh_file = Args.Households
  reporting_dir = Scenario_Dir + "\\Output\\_reportingtool" //need to create this dir in argument file
  output_dir = reporting_dir + "\\Transit_HH_Strata_Coverage" 
  temp_dir = output_dir + "\\temp"
  RunMacro("Create Directory", output_dir)
  RunMacro("Create Directory", temp_dir)
  scen_rts = Args.Routes
  
  // Creat TAZ_HHstrata file
  hh = null
  hh = CreateObject("df", hh_file)
  hh.group_by({"ZoneID", "market_segment"})
  hh.summarize({"WEIGHT"}, "sum")
  hh.spread("market_segment", "sum_WEIGHT",)
  TAZ_HHstrata_filename = output_dir + "/" + "HH_Strata_byTAZ.csv"
  hh.write_csv(TAZ_HHstrata_filename) 
  
  // Loop through each modes
  transit_modes = RunMacro("Get Transit Modes", TransModeTable) // get available transit mode in scenario
  transit_modes = {"all"} + transit_modes
  mode_list = {"nt", "lb", "eb", "brt", "cr", "lr", "all"}

  for mode in transit_modes do
    pos = ArrayPosition(mode_list, {mode},) //turn mode into integer because the RTS use integer
    // Create TOD_Mode_RTS selection
    opts = null
    opts.file = scen_rts
    {map, {rlyr, slyr}} = RunMacro("Create Map", opts)
    SetLayer(rlyr)
    if mode = "all" and TOD = "Daily" then
      n = SelectAll("selection")
    else if mode = "all" and TOD <> "Daily" then do
      qry = "Select * where " + TOD + "Headway >0"
      n = SelectByQuery("selection", "several", qry)
    end 
    else if mode <> "all" and TOD = "Daily" then do
      qry = "Select * where Mode = " + i2s(pos)
      n = SelectByQuery("selection", "several", qry)
    end
    else do
      qry = "Select * where " + TOD + "Headway >0 and Mode = " + i2s(pos)
      n = SelectByQuery("selection", "several", qry)
    end 

    // Create buffer for TOD_Mode_RTS selection
    buffer_dbd = temp_dir + "/" + TOD + "_" + mode + "_Routebuffer.dbd"
    if TypeOf(RouteBuffer) = "string" then RouteBuffer = s2r(RouteBuffer)
    CreateBuffers(buffer_dbd, "buffer", {"selection"}, "Value", {RouteBuffer}, {Interior: "Merged", Exterior: "Merged"})
    buffer_Lyr = AddLayer(map, "buffer", buffer_dbd, "buffer")

    //Add taz layer to create taz_buffer intersect
    buffer_intxDBF = temp_dir + "/" + TOD + "_" + mode +"_Routebuffer_TAZ_Intersect.dbf"
    {tlyr} = GetDBLayers(taz_file)
    tlyr = AddLayer(map, tlyr, taz_file, tlyr)
    ComputeIntersectionPercentages({tlyr,buffer_Lyr},buffer_intxDBF,) 
    int_vw = OpenTable("int_vw","DBASE",{buffer_intxDBF,})
    SetView(int_vw)
    num_Buffer = SelectByQuery("BufferSet", "Several", "Select * where AREA_1>0 and AREA_2>0",) // Select only intx shape within TAZ and buffer
    agg_vw = AggregateTable("agg",int_vw+"|BufferSet", "FFB", temp_dir + "/" + TOD + "_" + mode + "_" +"RouteBuffer_TAZ.bin", "AREA_1", 
            {{"PERCENT_1","sum", }}, {"Missing As Zero": "true"}) // here we know which TAZs make up the buffer and their pct

    //Join TAZ_Buffer to TAZ_HHstrata
    TAZ_Buffer = OpenTable("TAZ_Buffer","FFB",{temp_dir + "/" + TOD + "_" + mode + "_" +"RouteBuffer_TAZ.bin",})
    TAZ_HHstrata = OpenTable("TAZ_HHstrata","CSV", { TAZ_HHstrata_filename,})
    jn_vw1 = JoinViews("Buffer_HHstrata", TAZ_Buffer+".AREA_1", TAZ_HHstrata + ".ZoneID",)
    jn_vw2= JoinViews("TAZ_Buffer_HHstrata", tlyr + ".ID", jn_vw1 + "." + TAZ_Buffer + ".AREA_1", )
    segments = {"v0", "ilvi", "ihvi", "ilvs", "ihvs"}
    for segment in segments do
        CreateExpression(jn_vw2, segment + "_HH", "PERCENT_1 * " + segment,)
    end
    output_name1 = output_dir + "/" + TOD + "_" + mode +"Route_HHStrataReachedin" + R2S(RouteBuffer) + "Mi.csv"
    ExportView(jn_vw2 + "|", "CSV", output_name1, 
              {"ID", "MPO", "District", "County", "v0_HH", "ilvi_HH", "ihvi_HH", "ilvs_HH", "ihvs_HH"}, 
              {{"CSV Header", "True"}, { "Row Order", {{"ID", "Ascending"}} }})

    //Aggregate output by MPO/COUNTY/DISTRICT
    group_fields = {"MPO", "County", "District"}
    fields_to_sum = {"v0_HH", "ilvi_HH", "ihvi_HH", "ilvs_HH", "ihvs_HH"}
    for group_field in group_fields do
      df = null
      df = CreateObject("df", output_name1)
      df.group_by(group_field)
      df.summarize(fields_to_sum, "sum")
      df.mutate("Sum_HH", round(df.tbl.sum_v0_HH + df.tbl.sum_ilvi_HH + df.tbl.sum_ihvi_HH + df.tbl.sum_ilvs_HH + df.tbl.sum_ihvs_HH, 0))
      output_name2 = output_dir + "/" + TOD + "_" + mode +"Route_HHStrataReachedin" + R2S(RouteBuffer) + "Miby" + group_field + ".csv"
      df.write_csv(output_name2) 
    end
    RunMacro("Close All")
  end
  PutInRecycleBin(temp_dir)
EndMacro

//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                        Macro "HH_Strata_Estimator_Stop"
//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Macro "HH_Strata_Estimator_Stop" (Args, TOD, StopBuffer)

  // Set directory and create output folder
  Scenario_Dir = Args.[Scenario Folder]
  TransModeTable = Args.TransModeTable
  taz_file = Args.TAZs
  hh_file = Args.Households
  reporting_dir = Scenario_Dir + "\\Output\\_reportingtool" //need to create this dir in argument file
  output_dir = reporting_dir + "\\Transit_HH_Strata_Coverage" 
  temp_dir = output_dir + "\\temp"
  RunMacro("Create Directory", output_dir)
  RunMacro("Create Directory", temp_dir)
  scen_rts = Args.Routes
  
  // Creat TAZ_HHstrata file
  hh = null
  hh = CreateObject("df", hh_file)
  hh.group_by({"ZoneID", "market_segment"})
  hh.summarize({"WEIGHT"}, "sum")
  hh.spread("market_segment", "sum_WEIGHT",)
  TAZ_HHstrata_filename = output_dir + "/" + "HH_Strata_byTAZ.csv"
  hh.write_csv(TAZ_HHstrata_filename) 
  
  // Loop through each modes
  transit_modes = RunMacro("Get Transit Modes", TransModeTable) // get available transit mode in scenario
  transit_modes = {"all"} + transit_modes
  mode_list = {"nt", "lb", "eb", "brt", "cr", "lr", "all"}

  for mode in transit_modes do
    pos = ArrayPosition(mode_list, {mode},) //turn mode into integer because the RTS use integer
    // Create TOD_Mode_RTS selection
    opts = null
    opts.file = scen_rts
    {map, {rlyr, slyr}} = RunMacro("Create Map", opts)
    jn_vw = JoinViews("Stop_Route", slyr + ".Route_ID", rlyr + ".Route_ID",)
    SetView(jn_vw)
    if mode = "all" and TOD = "Daily" then
      n = SelectAll("selection")
    else if mode = "all" and TOD <> "Daily" then do
      qry = "Select * where " + TOD + "Headway >0"
      n = SelectByQuery("selection", "several", qry)
    end 
    else if mode <> "all" and TOD = "Daily" then do
      qry = "Select * where Mode = " + i2s(pos)
      n = SelectByQuery("selection", "several", qry)
    end
    else do
      qry = "Select * where " + TOD + "Headway >0 and Mode = " + i2s(pos)
      n = SelectByQuery("selection", "several", qry)
    end 

    // Create buffer for TOD_Mode_RTS selection
    SetLayer(slyr)
    buffer_dbd = temp_dir + "/" + TOD + "_" + mode + "_Stopbuffer.dbd"
    if TypeOf(StopBuffer) = "string" then StopBuffer = s2r(StopBuffer)
    CreateBuffers(buffer_dbd, "buffer", {"selection"}, "Value", {StopBuffer}, {Interior: "Merged", Exterior: "Merged"})
    buffer_Lyr = AddLayer(map, "buffer", buffer_dbd, "buffer")

    //Add taz layer to create taz_buffer intersect
    buffer_intxDBF = temp_dir + "/" + TOD + "_" + mode +"_Stopbuffer_TAZ_Intersect.dbf"
    {tlyr} = GetDBLayers(taz_file)
    tlyr = AddLayer(map, tlyr, taz_file, tlyr)
    ComputeIntersectionPercentages({tlyr,buffer_Lyr},buffer_intxDBF,) 
    int_vw = OpenTable("int_vw","DBASE",{buffer_intxDBF,})
    SetView(int_vw)
    num_Buffer = SelectByQuery("BufferSet", "Several", "Select * where AREA_1>0 and AREA_2>0",) // Select only intx shape within TAZ and buffer
    agg_vw = AggregateTable("agg",int_vw+"|BufferSet", "FFB", temp_dir + "/" + TOD + "_" + mode + "_" +"StopBuffer_TAZ.bin", "AREA_1", 
            {{"PERCENT_1","sum", }}, {"Missing As Zero": "true"}) // here we know which TAZs make up the buffer and their pct

    //Join TAZ_Buffer to TAZ_HHstrata
    TAZ_Buffer = OpenTable("TAZ_Buffer","FFB",{temp_dir + "/" + TOD + "_" + mode + "_" +"StopBuffer_TAZ.bin",})
    TAZ_HHstrata = OpenTable("TAZ_HHstrata","CSV", { TAZ_HHstrata_filename,})
    jn_vw1 = JoinViews("Buffer_HHstrata", TAZ_Buffer+".AREA_1", TAZ_HHstrata + ".ZoneID",)
    jn_vw2= JoinViews("TAZ_Buffer_HHstrata", tlyr + ".ID", jn_vw1 + "." + TAZ_Buffer + ".AREA_1", )
    segments = {"v0", "ilvi", "ihvi", "ilvs", "ihvs"}
    for segment in segments do
        CreateExpression(jn_vw2, segment + "_HH", "PERCENT_1 * " + segment,)
    end
    output_name1 = output_dir + "/" + TOD + "_" + mode +"Stop_HHStrataReachedin" + R2S(StopBuffer) + "Mi.csv"
    ExportView(jn_vw2 + "|", "CSV", output_name1, 
              {"ID", "MPO", "District", "County", "v0_HH", "ilvi_HH", "ihvi_HH", "ilvs_HH", "ihvs_HH"}, 
              {{"CSV Header", "True"}, { "Row Order", {{"ID", "Ascending"}} }})

    //Aggregate output by MPO/COUNTY/DISTRICT
    group_fields = {"MPO", "County", "District"}
    fields_to_sum = {"v0_HH", "ilvi_HH", "ihvi_HH", "ilvs_HH", "ihvs_HH"}
    for group_field in group_fields do
      df = null
      df = CreateObject("df", output_name1)
      df.group_by(group_field)
      df.summarize(fields_to_sum, "sum")
      df.mutate("Sum_HH", round(df.tbl.sum_v0_HH + df.tbl.sum_ilvi_HH + df.tbl.sum_ihvi_HH + df.tbl.sum_ilvs_HH + df.tbl.sum_ihvs_HH, 0))
      output_name2 = output_dir + "/" + TOD + "_" + mode +"Stop_HHStrataReachedin" + R2S(StopBuffer) + "Miby" + group_field + ".csv"
      df.write_csv(output_name2) 
    end
    RunMacro("Close All")
  end
  PutInRecycleBin(temp_dir)
  
EndMacro