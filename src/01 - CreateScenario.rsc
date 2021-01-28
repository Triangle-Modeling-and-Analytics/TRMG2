/*
Builds a scenario from master files
*/

Macro "Create Scenario" (Args)

  scen_dir = Args.[Scenario Folder]

  // Check if anything has already been created in the scenario directory
  dir = Args.scen_dir + "/inputs/*"
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
    RunMacro("Create Folder Structure", Args)
    // RunMacro("Copy TAZ", Args)
    // RunMacro("Create Scenario SE", Args)
    // RunMacro("Create Scenario Highway", Args)
    // RunMacro("Create Scenario Transit", Args)
  end
EndMacro

/*
- Creates input and output folders needed in the scenario directory
*/

Macro "Create Folder Structure" (Args)

  // copy the master directory structure to the scenario input directory
  opts = null
  opts.from = Args.master_dir
  opts.to = Args.scen_dir + "/inputs"
  opts.copy_files = "true"
  RunMacro("Copy Directory", opts)

  // Array of output directories to create
  a_dir = {
    "/outputs/taz",
    "/outputs/sedata",
    "/outputs/networks",
    "/outputs/skims",
    "/outputs/external",
    "/outputs/resident/generation",
    "/outputs/resident/destination",
    "/outputs/resident/mode",
    "/outputs/directionality",
    "/outputs/assignment",
    "/outputs/assignment/transit",
    "/outputs/summary",
  }

  for d = 1 to a_dir.length do
    dir = Args.scen_dir + a_dir[d]

    RunMacro("Create Directory", dir)
  end

  RunMacro("Close All")
EndMacro

/*
- copies the master TAZ layer into the scenario
- standardizes name
*/

Macro "Copy TAZ" (Args)
  UpdateProgressBar("Copy TAZ", 0)

  // Remove any dbd files in the taz directory
  dir = Args.scen_dir + "/inputs/tazs"
  a_dbds = RunMacro("Catalog Files", dir, "dbd")
  for i = 1 to a_dbds.length do
    DeleteDatabase(a_dbds[i])
  end

  // Create the TAZ file
  taz_dir = Args.master_dir + "\\tazs"
  a_files = GetDirectoryInfo(taz_dir + "/*.dbd", "File")
  if a_files.length > 1 then Throw(
    "There are multiple DBD files in the master TAZ folder.\n" +
    "Leave only the official TAZ layer of the model."
  )
  CopyDatabase(
    taz_dir + "\\" + a_files[1][1],
    Args.scen_dir + "\\inputs\\taz\\ScenarioTAZ.dbd"
  )

EndMacro

/*
- creates the scenario SE data
- standardizes name
*/

Macro "Create Scenario SE" (Args)
  UpdateProgressBar("Create Scenario SE", 0)

  // Remove any bin or dcb files in the directory
  dir = Args.scen_dir + "/inputs/sedata"
  a_dbds = RunMacro("Catalog Files", dir, {"bin", "dcb"})
  for i = 1 to a_dbds.length do
    DeleteFile(a_dbds[i])
  end

  // Make sure folder exists before exporting
  dir = Args.scen_dir + "/inputs/sedata"
  RunMacro("Create Directory", dir)

  // Export se data into the scenario folder
  master_se = OpenTable("master_se", "FFB", {Args.master_se})
  scen_se = Args.scen_dir + "/inputs/sedata/ScenarioSE.bin"
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
- uses the highway project manager
*/

Macro "Create Scenario Highway" (Args)
  UpdateProgressBar("Create Scenario Highway", 0)

  // Remove any dbd files in the directory
  dir = Args.scen_dir + "/inputs/networks"
  a_dbds = RunMacro("Catalog Files", dir, "dbd")
  for i = 1 to a_dbds.length do
    DeleteDatabase(a_dbds[i])
  end

  // Copy the master highway network into the scenario folder
  scen_hwy = Args.scen_dir + "/inputs/networks/ScenarioNetwork.dbd"
  if GetFileInfo(scen_hwy) <> null then DeleteFile(scen_hwy)
  CopyDatabase(Args.master_hwy, scen_hwy)

  // Update the network using the project manager
  opts = null
  opts.hwy_dbd = scen_hwy
  opts.proj_list = Args.scen_dir + "/HighwayProjectList.csv"
  opts.master_dbd = Args.master_hwy
  RunMacro("Highway Project Management", opts)

  RunMacro("Close All")
EndMacro

/*
- copies the master network into the scenario directory
- standardizes name
- uses the transit project manager
*/

Macro "Create Scenario Transit" (Args)
  UpdateProgressBar("Create Scenario Transit", 0)

  // Remove any RTS files in the directory
  scen_rts = Args.scen_dir + "/inputs/networks/ScenarioRoutes.dbd"
  if GetFileInfo(scen_rts) <> null then DeleteRouteSystem(scen_rts)

  // Create scenario RTS using project manager
  scen_dir = Args.scen_dir
  opts = null
  opts.master_rts = Args.master_rts
  opts.scen_hwy = Args.scen_dir + "/inputs/networks/ScenarioNetwork.dbd"
  opts.proj_list = scen_dir + "/TransitProjectList.csv"
  opts.centroid_qry = "TAZ <> null"
  RunMacro("Transit Project Management", opts)

  // Check that no centroids are marked for PNR. This will cause
  // transit skimming to crash.
  opts = null
  opts.file = Args.scen_dir + "/inputs/networks/ScenarioNetwork.dbd"
  {map, {nlyr, llyr}} = RunMacro("Create Map", opts)
  SetLayer(nlyr)
  qry = "Select * where TAZ <> null and PNR = 1"
  n = SelectByQuery("check", "several", qry)
  if n > 0 then Throw(
    "At least one centroid is marked as a PNR node.\n" +
    "Use the following query to find them: 'TAZ <> null and PNR = 1'"
  )
  CloseMap(map)
EndMacro
