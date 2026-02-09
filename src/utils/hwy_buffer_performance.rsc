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

  // Select corridor using the query
  {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})
  SetLayerVisibility(map + "|" + nlyr, "false")
  SetLayer(llyr)
  n1 = SelectByIDFile("corridor", "several", query_file)

  // Create buffer area using selected links
  buffer_dbd = proj_dir + "/" + name + "_" + buffer + "mi_buffer.dbd"
  CreateBuffers(buffer_dbd, "buffer", {"corridor"}, "Value", {s2r(buffer)}, {Interior: "Merged", Exterior: "Merged"})
  buffer_lyr = AddLayer(map, "buffer", buffer_dbd, "buffer")
  
  // Select links using the buffer area
  n2 = SelectByVicinity("corridor_buffer", "Several", buffer_lyr + "|", 0, {Inclusion: "Intersecting"})

  // Exclude links that are not highway roads
  hwy_query = "Select * where HCMTYPE <> 'CC' and HCMTYPE <> NULL and HCMTYPE <> 'TransitOnly'"
  n3 = SelectByQuery("corridor_buffer", "subset", hwy_query)

  // Define the line of all line fields to output in full spec format (except for ID, Dir and Length fields)
  {flds, specs} = GetFields(llyr, "All")
  flds = ExcludeArrayElements(flds, 1, 3)
  specs = ExcludeArrayElements(specs, 1, 3)

  // default copy for every field
  attrib = null
  for i=1 to flds.length do
    fld = flds[i][1]
    attrib.(fld) = "Copy"
  end
  
  // Define which line attributes will be split
  attrib.AB_Time_Daily = "Split"
  attrib.BA_Time_Daily = "Split"
  attrib.AB_VMT_Daily = "Split"
  attrib.BA_VMT_Daily = "Split"
  attrib.Total_VMT_Daily = "Split"
  attrib.AB_VHT_Daily = "Split"
  attrib.BA_VHT_Daily = "Split"
  attrib.Total_VHT_Daily = "Split"
  attrib.AB_Delay_Daily = "Split"
  attrib.BA_Delay_Daily = "Split"
  attrib.Total_Delay_Daily = "Split"
  attrib.Tot_Delay_AM = "Split"
  attrib.Tot_Delay_MD = "Split"
  attrib.Tot_Delay_PM = "Split"
  attrib.Tot_Delay_NT = "Split"

  //Then run the cuttin macro "Clip Lines":
  out_dbd = proj_dir + "/" + name + "_" + buffer + "mi_buffer_links.dbd"
  clip = RunMacro("Clip Lines", llyr + "|corridor_buffer",  buffer_lyr + "|", out_dbd, specs, attrib, , )
  clip_lyr = AddLayer(map, "clip", out_dbd, "master_links")
  
  // Aggregate
  SetLayer(clip_lyr)
  agg_vw = ComputeStatistics(clip_lyr + "|", "corridor_buffer_stats", proj_dir + "/" + name + "_" + buffer + "mi_buffer_summary.bin", "FFB", {"Strings", "False"})
  
  // Save map
  mapFile = proj_dir + "/" + name + "_" + buffer + "mi_buffer_map.map"
  SaveMap(map, mapFile)
  RunMacro("Close All")

EndMacro
