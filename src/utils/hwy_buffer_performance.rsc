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
  flds = {
    "RoadName",
    "HCMType",
    "ABLanes",
    "BALanes",
    "PostedSpeed",
    "HCMMedian",
    "DTWB",
    "p1ID",
    "p2ID",
    "p3ID",
    "p4ID",
    "ABPMCapE",
    "BAPMCapE",
    "AB_Speed_Daily",
    "BA_Speed_Daily",
    "AB_Time_Daily",
    "BA_Time_Daily",
    "AB_VOCE_DailyMax",
    "BA_VOCE_DailyMax",
    "AB_VOCD_DailyMax",
    "BA_VOCD_DailyMax",
    "AB_Flow_Daily",
    "BA_Flow_Daily",
    "Total_Flow_Daily",
    "Total_CV_Flow_Daily",
    "Total_SUT_Flow_Daily",
    "Total_MUT_Flow_Daily",
    "AB_VMT_Daily",
    "BA_VMT_Daily",
    "Total_VMT_Daily",
    "AB_VHT_Daily",
    "BA_VHT_Daily",
    "Total_VHT_Daily",
    "AB_Delay_Daily",
    "BA_Delay_Daily",
    "Total_Delay_Daily",
    "Tot_Delay_AM",
    "Tot_Delay_MD",
    "Tot_Delay_PM",
    "Tot_Delay_NT",
    "MPO",
    "County",
    "Tot_Flow_AM",
    "Tot_Flow_MD",
    "Tot_Flow_PM",
    "Tot_Flow_NT"
    }

  specs = {
    "master_links.RoadName",
    "master_links.HCMType",
    "master_links.ABLanes",
    "master_links.BALanes",
    "master_links.PostedSpeed",
    "master_links.HCMMedian",
    "master_links.DTWB",
    "master_links.p1ID",
    "master_links.p2ID",
    "master_links.p3ID",
    "master_links.p4ID",
    "master_links.ABPMCapE",
    "master_links.BAPMCapE",
    "master_links.AB_Speed_Daily",
    "master_links.BA_Speed_Daily",
    "master_links.AB_Time_Daily",
    "master_links.BA_Time_Daily",
    "master_links.AB_VOCE_DailyMax",
    "master_links.BA_VOCE_DailyMax",
    "master_links.AB_VOCD_DailyMax",
    "master_links.BA_VOCD_DailyMax",
    "master_links.AB_Flow_Daily",
    "master_links.BA_Flow_Daily",
    "master_links.Total_Flow_Daily",
    "master_links.Total_CV_Flow_Daily",
    "master_links.Total_SUT_Flow_Daily",
    "master_links.Total_MUT_Flow_Daily",
    "master_links.AB_VMT_Daily",
    "master_links.BA_VMT_Daily",
    "master_links.Total_VMT_Daily",
    "master_links.AB_VHT_Daily",
    "master_links.BA_VHT_Daily",
    "master_links.Total_VHT_Daily",
    "master_links.AB_Delay_Daily",
    "master_links.BA_Delay_Daily",
    "master_links.Total_Delay_Daily",
    "master_links.Tot_Delay_AM",
    "master_links.Tot_Delay_MD",
    "master_links.Tot_Delay_PM",
    "master_links.Tot_Delay_NT",
    "master_links.MPO",
    "master_links.County",
    "master_links.Tot_Flow_AM",
    "master_links.Tot_Flow_MD",
    "master_links.Tot_Flow_PM",
    "master_links.Tot_Flow_NT"
    }

  // Define value settings for each field (Split for VMT, VHT, Delay, Time and Cost fields, Copy for all other fields)
  attrib = null
  for i=1 to flds.length do
    fld = flds[i]
    if Position(fld, "VMT") > 0 or Position(fld, "VHT") > 0 or Position(fld, "Delay") > 0 or Position(fld, "Time") > 0 or Position(fld, "Cost") > 0 then
      attrib.(fld) = "Split"
    else attrib.(fld) = "Copy"
  end

  //Then run the cuttin macro "Clip Lines":
  out_dbd = proj_dir + "/" + name + "_" + buffer + "mi_buffer_links.dbd"
  clip = RunMacro("Clip Lines", llyr + "|corridor_buffer",  buffer_lyr + "|", out_dbd, specs, attrib, , )
  clip_lyr = AddLayer(map, "clip", out_dbd, "master_links")
  
  // Aggregate
  SetLayer(clip_lyr)
  agg_vw = ComputeStatistics(clip_lyr + "|", "corridor_buffer_stats", proj_dir + "/" + name + "_" + buffer + "mi_buffer_summary.bin", "FFB", {"Strings", "False"})
  ExportView(agg_vw + "|", "CSV", proj_dir + "/" + name + "_" + buffer + "mi_buffer_summary.csv", , {"CSV Header": "true"})
  ExportView(clip_lyr + "|", "CSV", proj_dir + "/" + name + "_" + buffer + "mi_buffer_links.csv", , {"CSV Header": "true"})
  
  // Save map
  mapFile = proj_dir + "/" + name + "_" + buffer + "mi_buffer_map.map"
  SaveMap(map, mapFile)
  RunMacro("Close All")

EndMacro
