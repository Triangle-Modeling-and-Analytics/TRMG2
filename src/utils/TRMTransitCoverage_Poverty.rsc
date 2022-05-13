Macro "Open Transit Poverty HH Coverage Dbox" (Args)
	RunDbox("Transit Poverty HH Coverage", Args)
endmacro

dBox "Transit Poverty HH Coverage" (Args) location: center, center, 80, 20
  Title: "Transit Poverty HH Coverage" toolbox NoKeyBoard

  // What happens when the "x" is clicked
  close do
    return()
  enditem

  // Quit Button
  button 5, 18, 10 Prompt:"Quit" do
    Return(1)
  enditem

  init do
    
    static BG_Layer_CDF, Census_Poverty_Data_Dir
    static Radius_list, StopRadius_Index, StopBuffer, RouteRadius_Index, RouteBuffer
    static TOD, TOD_list, TOD_Index, UseStop, UseRoute

    Radius_list = {"0.1","0.25","0.5","0.75","1","1.5","2","2.5","3"}
    TOD_list = Args.periods + {"Daily"}
    poverty_dir = Args.[Base Folder] + "\\other\\_reportingtool"

    EnableItem("Select Stop Radius")
	  EnableItem("Select Route Radius")

  enditem

  // BG Geo file text and button
  text 5, 1 variable: "Census Block Group Shapefile:"
  text same, after, 40 variable: BG_Layer_CDF framed
  button after, same, 6 Prompt: "..." do

    on escape goto nodir
    BG_Layer_CDF = ChooseFile({{"CDF", "*.cdf"}}, "Choose the Block Group Geographical File", {"Initial Directory": poverty_dir})

    nodir:
    on error, notfound, escape default
  enditem  
  
  text 5, 4 variable: "Census Poverty Data:"
  text same, after, 40 variable: Census_Poverty_Data_Dir framed
  button after, same, 6 Prompt: "..." do

    on escape goto nodir
    Census_Poverty_Data_Dir = ChooseFile({{"CSV", "*.CSV"}}, "Choose the Census Poverty Data File", {"Initial Directory": poverty_dir})

    nodir:
    on error, notfound, escape default
  enditem  

  // Select Radius
  Popdown Menu "Select Stop Radius" 29,8,10,5 Prompt: "Choose Stop Radius (Miles)" 
    List: Radius_list Variable: StopRadius_Index do
    StopBuffer = Radius_list[StopRadius_Index]
  enditem

  Popdown Menu "Select Route Radius" 30,10,10,5 Prompt: "Choose Route Radius (Miles)" 
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
  button 40, 18, 30 Prompt:"Generate Transit Coverage" do // button p1,p2,p3, p1 horizontal, p2 vertical, p3 length
    if UseStop = 1 and (StopBuffer = null or TOD = null) then ShowMessage("Please make a selection for all drop down lists.")
    else if UseStop = 1 then RunMacro("Poverty_HH_Estimator_Stop", Args, BG_Layer_CDF, Census_Poverty_Data_Dir, TOD, StopBuffer) 
		
    if UseRoute = 1 and (RouteBuffer = null or TOD = null) then ShowMessage("Please make a selection for all drop down lists.")
    else if UseRoute = 1 then RunMacro("Poverty_HH_Estimator_Route",  Args, BG_Layer_CDF, Census_Poverty_Data_Dir, TOD, RouteBuffer)

    ShowMessage("Reports have been created successfully.")
  Enditem

enddbox

//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                        Macro "Poverty_HH_Estimator_Route"
//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Macro "Poverty_HH_Estimator_Route" (Args, BG_Layer_CDF, Census_Poverty_Data_Dir, TOD, RouteBuffer)

  // Set directory and create output folder
  Scenario_Dir = Args.[Scenario Folder]
  master_dir = Args.[Master Folder]
  TransModeTable = Args.TransModeTable
  masterTransModeTable = Args.[Master Folder] + "\\networks\\transit_mode_table.csv"
  taz_file = Args.TAZs
  se_file = Args.SE
  reporting_dir = Scenario_Dir + "\\Output\\_summaries\\_reportingtool" //need to create this dir in argument file
  output_dir = reporting_dir + "\\Transit_Poverty_HH_Coverage" 
  temp_dir = output_dir + "\\temp"
  RunMacro("Create Directory", output_dir)
  RunMacro("Create Directory", temp_dir)
  scen_rts = Args.Routes
  scen_hwy = Args.Links
  
  // Creat TAZ BG intersect layer to get TAZ poverty pct
  {map, {tlyr}} = RunMacro("Create Map", {file: taz_file})
  {bglyr} = GetDBLayers(BG_Layer_CDF)
  bglyr = AddLayer(map, bglyr, BG_Layer_CDF, bglyr)
  SetLayer(bglyr)

  IntersectDBF = temp_dir + "/TAZ_BG_Intersect.dbf"
  ComputeIntersectionPercentages({tlyr, bglyr}, IntersectDBF,) 

  int_vw = OpenTable("int_vw","DBASE",{IntersectDBF,})
  Poverty = OpenTable("Poverty", "CSV", {Census_Poverty_Data_Dir}, {{"Shared", "True"}}) // From census table B17017 
  BG_Poverty = JoinViews("BG_Poverty", bglyr+".GEOID", Poverty + ".Geo_FIPS",)
  TAZ_BG_Poverty = JoinViews("TAZ_BG_Poverty", int_vw + ".AREA_2", BG_Poverty+ "."+ bglyr +".ID",)
  expr1 = CreateExpression(TAZ_BG_Poverty, "BG_TotHH", "PERCENT_2 * total",)
  expr2 = CreateExpression(TAZ_BG_Poverty, "BG_PovertyHH", "PERCENT_2 * poverty",)
  SetView(TAZ_BG_Poverty)
  num_TAZ = SelectByQuery("TAZset", "Several", "Select * where AREA_1>0 and AREA_2>0",) // Select only intx shape within TAZ
  agg_vw = AggregateTable(
        "agg", TAZ_BG_Poverty + "|TAZset", "FFB", temp_dir + "/TAZ_Poverty.bin", "AREA_1", 
        {{"BG_TotHH", "SUM", }, {"BG_PovertyHH", "SUM", }}, {"Missing As Zero": "true"})
  
  RunMacro("Close All")

  // Loop through each modes
  transit_modes = RunMacro("Get Transit Modes", TransModeTable) // get available transit mode in scenario
  transit_modes = {"all"} + transit_modes

  // Build mode crosswalk between id and abbr
  mode_vw = OpenTable("mode", "CSV", {TransModeTable})
  abbr = V2A(GetDataVector(mode_vw + "|", "abbr", ))
  mode_id = V2A(GetDataVector(mode_vw + "|", "Mode_ID", ))

  for mode in transit_modes do
    pos = abbr.position(mode)
    if pos > 0 then int = mode_id[pos] //turn mode into integer because the RTS use integer
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
      qry = "Select * where Mode = " + i2s(int)
      n = SelectByQuery("selection", "several", qry)
    end
    else do
      qry = "Select * where " + TOD + "Headway >0 and Mode = " + i2s(int)
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

    //Join TAZ_Buffer to TAZ_Poverty then to TAZ layer
    TAZ_Buffer = OpenTable("TAZ_Buffer","FFB",{temp_dir + "/" + TOD + "_" + mode + "_" +"RouteBuffer_TAZ.bin",})
    TAZ_Poverty = OpenTable("TAZ_Buffer","FFB",{ temp_dir + "/TAZ_Poverty.bin",})
    SE = OpenTable("SE","FFB",{se_file,})
    jn_vw1 = JoinViews("Buffer_Poverty", TAZ_Buffer+".AREA_1", TAZ_Poverty + ".AREA_1",)
    jn_vw2 = JoinViews("SE_Buffer_Poverty", SE + ".TAZ", jn_vw1 + "." + TAZ_Buffer + ".AREA_1",)
    jn_vw3= JoinViews("TAZ_SE_Buffer_Poverty", tlyr + ".ID", jn_vw2 + "." + SE + ".TAZ", )
    CreateExpression(jn_vw3, "Poverty_Pct", "if BG_TotHH > 0 then BG_PovertyHH/BG_TotHH else 0",)
    CreateExpression(jn_vw3, "Poverty_HH", "Poverty_Pct * HH * PERCENT_1",)
    output_name1 = output_dir + "/" + TOD + "_" + mode +"Route_PovertyReachedin" + R2S(RouteBuffer) + "Mi.csv"
    ExportView(jn_vw3 + "|", "CSV", output_name1, 
              {"TAZ", "MPO", "County", "HH", "Poverty_Pct", "Poverty_HH"}, 
              {{"CSV Header", "True"}, { "Row Order", {{"TAZ", "Ascending"}} }})

    //Aggregate output by MPO/COUNTY/DISTRICT
    group_fields = {"MPO", "County"}
    fields_to_sum = {"HH", "Poverty_HH"}
    for group_field in group_fields do
      df = null
      df = CreateObject("df", output_name1)
      df.group_by(group_field)
      df.summarize(fields_to_sum, "sum")
      df.mutate("Poverty_Pct", df.tbl.sum_Poverty_HH/df.tbl.sum_HH)
      output_name2 = output_dir + "/" + TOD + "_" + mode +"Route_PovertyReachedin" + R2S(RouteBuffer) + "Miby" + group_field + ".csv"
      df.write_csv(output_name2) 
    end
    RunMacro("Close All")
  end
  
  //Delete temp files
  files = GetDirectoryInfo(temp_dir + "/*", "File")
  for i = 1 to files.length do
    file = files[i][1]
    filepath = temp_dir + "/" + file
    DeleteFile(filepath)
  end
  RemoveDirectory(temp_dir)
EndMacro

//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                        Macro "Poverty_HH_Estimator_Stop"
//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Macro "Poverty_HH_Estimator_Stop" (Args, BG_Layer_CDF, Census_Poverty_Data_Dir, TOD, StopBuffer)

  // Set directory and create output folder
  Scenario_Dir = Args.[Scenario Folder]
  TransModeTable = Args.TransModeTable
  masterTransModeTable = Args.[Master Folder] + "\\networks\\transit_mode_table.csv"
  taz_file = Args.TAZs
  se_file = Args.SE
  reporting_dir = Scenario_Dir + "\\Output\\_summaries\\_reportingtool"
  output_dir = reporting_dir + "\\Transit_Poverty_HH_Coverage" 
  temp_dir = output_dir + "\\temp"
  RunMacro("Create Directory", output_dir)
  RunMacro("Create Directory", temp_dir)
  scen_rts = Args.Routes
  scen_hwy = Args.Links
  
  // Creat TAZ BG intersect layer to get TAZ poverty pct
  {map, {tlyr}} = RunMacro("Create Map", {file: taz_file})
  {bglyr} = GetDBLayers(BG_Layer_CDF)
  bglyr = AddLayer(map, bglyr, BG_Layer_CDF, bglyr)
  SetLayer(bglyr)

  IntersectDBF = temp_dir + "/TAZ_BG_Intersect.dbf"
  ComputeIntersectionPercentages({tlyr, bglyr}, IntersectDBF,) 

  int_vw = OpenTable("int_vw","DBASE",{IntersectDBF,})
  Poverty = OpenTable("Poverty", "CSV", {Census_Poverty_Data_Dir}, {{"Shared", "True"}}) // From census table B17017 
  BG_Poverty = JoinViews("BG_Poverty", bglyr+".GEOID", Poverty + ".Geo_FIPS",)
  TAZ_BG_Poverty = JoinViews("TAZ_BG_Poverty", int_vw + ".AREA_2", BG_Poverty+ "."+ bglyr +".ID",)
  expr1 = CreateExpression(TAZ_BG_Poverty, "BG_TotHH", "PERCENT_2 * total",)
  expr2 = CreateExpression(TAZ_BG_Poverty, "BG_PovertyHH", "PERCENT_2 * poverty",)
  SetView(TAZ_BG_Poverty)
  num_TAZ = SelectByQuery("TAZset", "Several", "Select * where AREA_1>0 and AREA_2>0",) // Select only intx shape within TAZ
  agg_vw = AggregateTable(
        "agg", TAZ_BG_Poverty + "|TAZset", "FFB", temp_dir + "/TAZ_Poverty.bin", "AREA_1", 
        {{"BG_TotHH", "SUM", }, {"BG_PovertyHH", "SUM", }}, {"Missing As Zero": "true"})
  
  RunMacro("Close All")

  // Loop through each modes
  transit_modes = RunMacro("Get Transit Modes", TransModeTable) // get available transit mode in scenario
  transit_modes = {"all"} + transit_modes

  // Build mode crosswalk between id and abbr
  mode_vw = OpenTable("mode", "CSV", {TransModeTable})
  abbr = V2A(GetDataVector(mode_vw + "|", "abbr", ))
  mode_id = V2A(GetDataVector(mode_vw + "|", "Mode_ID", ))
  //mode_list = {"nt", "lb", "eb", "brt", "cr", "lr", "all"}

  for mode in transit_modes do
    pos = abbr.position(mode)
    if pos > 0 then int = mode_id[pos] //turn mode into integer because the RTS use integer
    
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
      qry = "Select * where Mode = " + i2s(int)
      n = SelectByQuery("selection", "several", qry)
    end
    else do
      qry = "Select * where " + TOD + "Headway >0 and Mode = " + i2s(int)
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
    ComputeIntersectionPercentages({tlyr, buffer_Lyr}, buffer_intxDBF,) 
    int_vw = OpenTable("int_vw","DBASE", {buffer_intxDBF,})
    SetView(int_vw)
    num_Buffer = SelectByQuery("BufferSet", "Several", "Select * where AREA_1>0 and AREA_2>0",) // Select only intx shape within TAZ and buffer
    agg_vw = AggregateTable("agg",int_vw+"|BufferSet", "FFB", temp_dir + "/" + TOD + "_" + mode + "_StopBuffer_TAZ.bin", "AREA_1", 
            {{"PERCENT_1","sum", }}, {"Missing As Zero": "true"}) // here we know which TAZs make up the buffer and their pct

    //Join TAZ_Buffer to TAZ_Poverty then to TAZ layer
    TAZ_Buffer = OpenTable("TAZ_Buffer","FFB",{temp_dir + "/" + TOD + "_" + mode +"_StopBuffer_TAZ.bin",})
    TAZ_Poverty = OpenTable("TAZ_Buffer","FFB",{ temp_dir + "/TAZ_Poverty.bin",})
    SE = OpenTable("SE","FFB",{se_file,})
    jn_vw1 = JoinViews("Buffer_Poverty", TAZ_Buffer+".AREA_1", TAZ_Poverty + ".AREA_1",)
    jn_vw2 = JoinViews("SE_Buffer_Poverty", SE + ".TAZ", jn_vw1 + "." + TAZ_Buffer + ".AREA_1",)
    jn_vw3= JoinViews("TAZ_SE_Buffer_Poverty", tlyr + ".ID", jn_vw2 + "." + SE + ".TAZ", )
    CreateExpression(jn_vw3, "Poverty_Pct", "if BG_TotHH > 0 then BG_PovertyHH/BG_TotHH else 0",)
    CreateExpression(jn_vw3, "Poverty_HH", "Poverty_Pct * HH * PERCENT_1",)
    output_name1 = output_dir + "/" + TOD + "_" + mode +"Stop_PovertyReachedin" + R2S(StopBuffer) + "Mi.csv"
    ExportView(jn_vw3 + "|", "CSV", output_name1, 
              {"TAZ", "MPO", "County", "HH", "Poverty_Pct", "Poverty_HH"}, 
              {{"CSV Header", "True"}, { "Row Order", {{"TAZ", "Ascending"}} }})

    //Aggregate output by MPO/COUNTY/DISTRICT
    group_fields = {"MPO", "County"}
    fields_to_sum = {"HH", "Poverty_HH"}
    for group_field in group_fields do
      df = null
      df = CreateObject("df", output_name1)
      df.group_by(group_field)
      df.summarize(fields_to_sum, "sum")
      df.mutate("Poverty_Pct", df.tbl.sum_Poverty_HH/df.tbl.sum_HH)
      output_name2 = output_dir + "/" + TOD + "_" + mode +"Stop_PovertyReachedin" + R2S(StopBuffer) + "Miby" + group_field + ".csv"
      df.write_csv(output_name2) 
    end
    RunMacro("Close All")
  end

  //Delete temp files
  files = GetDirectoryInfo(temp_dir + "/*", "File")
  for i = 1 to files.length do
    file = files[i][1]
    filepath = temp_dir + "/" + file
    DeleteFile(filepath)
  end
  RemoveDirectory(temp_dir)
EndMacro