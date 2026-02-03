Macro "Open Highway Buffer Performance Dbox" (Args)
	RunDbox("Highway Buffer Performance", Args)
endmacro

dBox "Highway Buffer Performance" (Args) location: center, center, 60, 12
  Title: "Highway Buffer Performance" toolbox NoKeyBoard

  // What happens when the "x" is clicked
  close do
    return()
  enditem


  init do
    
    static scen_dir,radius_list, radius_Index, buffer, query_file

    scen_dir = Args.[Scenarios Folder]
    radius_list = {"0.25", "0.5","0.75","1"}

    EnableItem("Select Buffer Radius")

  enditem

  Text 20, 1, 15 Prompt: "Selected Scenario:" Variable: "(current scenario)"
  
  // Select Link Query
  Edit Text 21, after, 25 Prompt: "Select Link IDs CSV:" Variable: query_file
  Button after, same, 5, 1 Prompt: "..." do
    on error, escape goto skip2
    query_file = ChooseFile({{"Query (*.csv)", "*.csv"}}, "Choose Link ID File", {"Initial Directory": scen_dir})
    skip2:
    on error default
  enditem

  // Select Radius
  Popdown Menu "Select Buffer Radius" 29, after, 10 Prompt: "Choose Buffer Radius (Miles)" 
    List: radius_list Variable: radius_Index do
    buffer = radius_list[radius_Index]
  enditem
  
  // Make Map Button
  button 15, 10, 10 Prompt:"Run" do 
    if buffer = null or query_file = null then ShowMessage("Please make a selection for all drop down lists.")
    else RunMacro("Hwy_Buffer_Performance_Agg", Args, buffer, query_file) 

    ShowMessage("Reports have been created successfully.")
  Enditem

  // Quit Button
  button 35, 10, 10 Prompt:"Quit" do
    Return(1)
  enditem

enddbox

//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                        Macro "Hwy_Buffer_Performance_Agg"
//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Macro "Hwy_Buffer_Performance_Agg" (Args, buffer, query_file)

  // Set directory and create output folder
  Scenario_Dir = Args.[Scenario Folder]
  hwy_dbd = Args.Links
  {, , name, } = SplitPath(query_file)
  reporting_dir = Scenario_Dir + "\\Output\\_summaries"
  output_dir = reporting_dir + "\\Highway_Buffer_Performance" 
  proj_dir = output_dir + "\\" + name
  RunMacro("Create Directory", output_dir)
  RunMacro("Create Directory", proj_dir)

  // Select links using the query
  {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})
  SetLayer(llyr)
  n1 = SelectByIDFile("hwy_selection", "several", query_file)
  /*
  // Create buffer area using selected links
  buffer_dbd = temp_dir + "/" + name + "_" + buffer + "mi_buffer.dbd"
  
  CreateBuffers(buffer_dbd, "buffer", {"hwy_selection"}, "Value", {buffer}, {Interior: "Merged", Exterior: "Merged"})
  buffer_lyr = AddLayer(map, "buffer", buffer_dbd, "buffer")
  */
  // Select links using the buffer distance
  n2 = SelectByVicinity("hwy_buffer", "Several", llyr + "|hwy_selection", s2r(buffer), {Inclusion: "Intersecting"})

  // Exclude links that are not highway roads
  hwy_query = "Select * where HCMTYPE <> 'CC' and HCMTYPE <> NULL and HCMTYPE <> 'TransitOnly'"
  n3 = SelectByQuery ("hwy_buffer", "Subset", hwy_query)

  // Aggregate
  agg_vw = ComputeStatistics("hwy_buffer", "hwy_buffer_stats", proj_dir + "/" + name + "_" + buffer + "mi_buffer_summary.bin", "FFB", {"Strings", "False"})

  RunMacro("Close All")

EndMacro
