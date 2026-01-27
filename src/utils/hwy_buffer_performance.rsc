Macro "Open Highway Buffer Performance Dbox" (Args)
	RunDbox("Highway Buffer Performance", Args)
endmacro

dBox "Highway Buffer Performance" (Args) location: center, center, 80, 20
  Title: "Highway Buffer Performance" toolbox NoKeyBoard

  // What happens when the "x" is clicked
  close do
    return()
  enditem

  // Quit Button
  button 5, 18, 10 Prompt:"Quit" do
    Return(1)
  enditem

  init do
    
    static scen_dir,radius_list, radius_Index, buffer, sl_query
    static tod, tod_list, tod_Index

    scen_dir = Args.[Scenarios Folder]
    radius_Index = {"0.5","0.75","1"}
    tod_list = Args.periods + {"Daily"}

    EnableItem("Select Buffer Radius")

  enditem

  // Select Link Query
  Edit Text same, after, 15 Prompt: "Select Link Query:" Variable: sl_query
  Button after, same, 5, 1 Prompt: "..." do
    on error, escape goto skip2
    sl_query = ChooseFile({{"Query (*.qry)", "*.qry"}}, "Choose Select Link Query", {"Initial Directory": scen_dir})
    skip2:
    on error default
  enditem

  // Select Radius
  Popdown Menu "Select Buffer Radius" 35,1,10,5 Prompt: "Choose Buffer Radius (Miles)" 
    List: radius_list Variable: radius_Index do
    buffer = radius_list[radius_Index]
  enditem
  
  // Select TOD
  Popdown Menu "Select TOD" 17,14,10,5 Prompt: "Choose TOD" 
    List: tod_list Variable: tod_Index do
    tod = tod_list[tod_Index]
  enditem
  
  // Make Map Button
  button 40, 18, 30 Prompt:"Generate Highway Buffer Performance" do 
    if buffer = null or tod = null then ShowMessage("Please make a selection for all drop down lists.")
    else RunMacro("Highway_Buffer_Performance_Aggregation", Args, tod, buffer) 
  Enditem

    ShowMessage("Reports have been created successfully.")
  Enditem

enddbox

//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                        Macro "Highway_Buffer_Performance_Aggregation"
//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Macro "Highway_Buffer_Performance_Aggregation" (Args, tod, buffer, sl_query)

  // Set directory and create output folder
  Scenario_Dir = Args.[Scenario Folder]
  hwy_dbd = Args.Links
  reporting_dir = Scenario_Dir + "\\Output\\_summaries"
  output_dir = reporting_dir + "\\Highway_Buffer_Performance" 
  //temp_dir = output_dir + "\\temp"
  RunMacro("Create Directory", output_dir)
  //RunMacro("Create Directory", temp_dir)

  // Select links in the buffer area for selected highway set
  {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})
  SetLayer(llyr)
  n1 = SelectByQuery("hwy_selection", "several", sl_query)
  if TypeOf(buffer) = "string" then buffer = s2r(buffer)
  n2 = SelectByVicinity("hwy_buffer", "Several", llyr + "|hwy_selection", buffer, )

  // Aggregate
  {, , name, } = SplitPath(sl_query)
  agg_vw = ComputeStatistics("hwy_buffer", "hwy_buffer_stats", output_dir + "/" + name + "_" +buffer + "mi_buffer_summary.csv", "CSV", {"Strings", "False"})

  RunMacro("Close All")

EndMacro
