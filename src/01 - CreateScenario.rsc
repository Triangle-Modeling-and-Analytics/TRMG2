/*
Builds a scenario from master files
*/

Macro "Create Scenario" (Args)

  pbar = CreateObject("G30 Progress Bar", "Scenario Creation", "False", )

  scen_dir = Args.[Scenario Folder]
  // Check if anything has already been created in the scenario directory
  dir = Args.[Input Folder] + "/*"
  if GetDirectoryInfo(dir, "All") <> null then do
    opts = null
    opts.Buttons = "YesNo"
    opts.Caption = "Note"
    str = "The input folder already contains information.\n" +
      "Continuing will overwrite any manual changes made.\n" +
      "(The output folder will not be modified.)\n" +
      "Are you sure you want to continue?"
    yesno = MessageBox(str, opts)
  end

  if yesno = "Yes" or yesno = null then do
    RunMacro("Check for Creation Files", Args)
    RunMacro("Create Folder Structure", Args)
    RunMacro("Copy TAZ", Args)
    RunMacro("Create Scenario SE", Args)
    RunMacro("Create Scenario Roadway", Args)
    RunMacro("Create Scenario Transit", Args)
  end

  ShowMessage("Scenario Created")
EndMacro

/*

*/

Macro "Check for Creation Files" (Args)

  scen_dir = Args.[Scenario Folder]

  // Ensure the minimum files are present
  if GetDirectoryInfo(scen_dir, "All") = null then Throw(
    "The scenario directory does not exist.\n" +
    "Scenario Directory: \n" +
    scen_dir
  )
  else if GetFileInfo(scen_dir + "/RoadwayProjectList.csv") = null then Throw(
    "The scenario directory is missing RoadwayProjectList.csv"
  )
  else if GetFileInfo(scen_dir + "/TransitProjectList.csv") = null then Throw(
    "The scenario directory is missing TransitProjectList.csv"
  )
endmacro

/*
Creates input and output folders needed in the scenario directory
*/

Macro "Create Folder Structure" (Args)

  // copy the master directory structure to the scenario input directory
  opts = null
  opts.from = Args.[Master Folder]
  opts.to = Args.[Input Folder]
  opts.copy_files = "true"
  RunMacro("Copy Directory", opts)

  // Array of output directories to create
  a_dir = {
    "/accessibility",
    "/airport",
    "/tazs",
    "/sedata",
    "/networks",
    "/skims/roadway",
    "/skims/transit",
    "/skims/nonmotorized",
    "/external",
    "/cv",
    "/university",
    "/resident/disagg_model",
    "/resident/population_synthesis",
    "/resident/dc",
    "/resident/mode",
    "/resident/mode/probabilities",
    "/resident/parking",
    "/resident/mode/logsums",
    "/resident/mode/utilities",
    "/resident/mode/model_files",
    "/resident/nhb/generation",
    "/resident/nhb/dc",
    "/resident/nonmotorized",
    "/resident/trip_matrices",
    "/assignment",
    "/assignment/transit",
    "/assignment/roadway",
    "/_summaries",
    "/_summaries/trip_conservation",
    "/_summaries/MOVES"
  }

  for d = 1 to a_dir.length do
    dir = Args.[Output Folder] + a_dir[d]
    RunMacro("Create Directory", dir)
  end

EndMacro

/*
- copies the master TAZ layer into the scenario
- standardizes name
*/

Macro "Copy TAZ" (Args)

  // Remove any dbd files in the taz directory
  dir = Args.[Input Folder] + "/tazs"
  a_dbds = RunMacro("Catalog Files", {dir: dir, ext: "dbd"})
  for i = 1 to a_dbds.length do
    DeleteDatabase(a_dbds[i])
  end

  // Create the TAZ file
  CopyDatabase(Args.[Master TAZs], Args.[Input TAZs])

EndMacro

/*
- creates the scenario SE data
- standardizes name
*/

Macro "Create Scenario SE" (Args)

  // Remove any bin or dcb files in the directory
  dir = Args.[Input Folder] + "/sedata"
  a_dbds = RunMacro("Catalog Files", {dir: dir, ext: {"bin", "dcb", "bxl"}})
  for i = 1 to a_dbds.length do
    DeleteFile(a_dbds[i])
  end

  // Make sure folder exists before exporting
  dir = Args.[Input Folder] + "/sedata"
  RunMacro("Create Directory", dir)

  // Export se data into the scenario folder
  master_se = OpenTable("master_se", "FFB", {Args.[Master SE]})
  scen_se = Args.[Input SE]
  if GetFileInfo(scen_se) <> null then DeleteTableFiles("FFB", scen_se, )
  ExportView(
    master_se + "|",
    "FFB",
    scen_se,,
  )
  CloseView(master_se)

  RunMacro("Close All")
EndMacro

/*
- copies the master network into the scenario directory
- standardizes name
- uses the roadway project manager
*/

Macro "Create Scenario Roadway" (Args)

  // Remove any dbd files in the directory
  dir = Args.[Input Folder] + "/networks"
  a_dbds = RunMacro("Catalog Files", {dir: dir, ext: "dbd"})
  for i = 1 to a_dbds.length do
    DeleteDatabase(a_dbds[i])
  end

  // Copy the master roadway network into the scenario folder
  master_hwy = Args.[Master Links]
  scen_hwy = Args.[Input Links]
  if GetFileInfo(scen_hwy) <> null then DeleteFile(scen_hwy)
  CopyDatabase(master_hwy, scen_hwy)

  // Update the network using the project manager
  opts = null
  opts.hwy_dbd = scen_hwy
  opts.proj_list = Args.[Scenario Folder] + "/RoadwayProjectList.csv"
  opts.master_dbd = master_hwy
  RunMacro("Roadway Project Management", opts)

  RunMacro("Close All")
EndMacro

/*
- copies the master route system into the scenario directory
- standardizes name
- uses the transit project manager
*/

Macro "Create Scenario Transit" (Args)

  // Remove any RTS files in the directory
  scen_rts = Args.[Input Routes]
  if GetFileInfo(scen_rts) <> null then DeleteRouteSystem(scen_rts)

  // Create scenario RTS using project manager
  scen_dir = Args.[Scenario Folder]
  opts = null
  opts.master_rts = Args.[Master Routes]
  opts.scen_hwy = Args.[Input Links]
  opts.proj_list = scen_dir + "/TransitProjectList.csv"
  opts.centroid_qry = "Centroid = 1"
  opts.link_qry = "HCMType <> null and HCMType <> 'CC'"
  {, , rts_name, ext} = SplitPath(scen_rts)
  opts.output_rts_file = rts_name + ext
  RunMacro("Transit Project Management", opts)

  // Check that no centroids are marked for PNR. This will cause
  // transit skimming to crash.
  opts = null
  opts.file = scen_rts
  {map, {rlyr, slyr, , nlyr, llyr}} = RunMacro("Create Map", opts)
  SetLayer(nlyr)
  qry = "Select * where Centroid = 1 and PNR = 1"
  n = SelectByQuery("check", "several", qry)
  if n > 0 then Throw(
    "At least one centroid is marked as a PNR node.\n" +
    "Use the following query to find them: 'Centroid = 1 and PNR = 1'"
  )

  CloseMap(map)
EndMacro
