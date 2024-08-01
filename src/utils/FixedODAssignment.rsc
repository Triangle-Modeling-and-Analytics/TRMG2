/*
The purpose of this tool to is allow supply side changes to be evaluated
quickly without affecting the demand (OD matrix).
*/
Macro "Open Fixed OD Dbox" (Args)
	RunDbox("FixedOD", Args)
endmacro
dBox "FixedOD" (Args) center, center, 50, 8 Title: "Fixed OD Assignment" Help: "test" toolbox

  init do
    static ref_scen_dir, sl_query
    scen_dir = Args.[Scenarios Folder]
  enditem

  close do
    return()
  enditem

  Edit Text 15, 1, 15 Prompt: "Reference Scenario:" Variable: ref_scen_dir
  Button after, same, 5, 1 Prompt: "..." do
    on error, escape goto skip1
    ref_scen_dir = ChooseDirectory("Choose Full Scenario Folder", {"Initial Directory": scen_dir})
    skip1:
    on error default
  enditem

  Text 15, after, 15 Prompt: "New Scenario:" Variable: "(current scenario)"

  Edit Text same, after, 15 Prompt: "Select Link Query:" Variable: sl_query
  Button after, same, 5, 1 Prompt: "..." do
    on error, escape goto skip2
    sl_query = ChooseFile({{"Query (*.qry)", "*.qry"}}, "Choose Select Link Query", {"Initial Directory": scen_dir})
    skip2:
    on error default
  enditem
  Text after, same, 10 Variable: "(optional)"

  Button 12, 6.5 Prompt: "Run" do
    mr = CreateObject("Model.Runtime")
    Args = mr.GetValues()
    if ref_scen_dir = Args.[Scenario Folder] then do
        Throw("The full scenario and current scenario cannot be the same")
        return()
    end
    opts.ref_scen_dir = ref_scen_dir
    opts.sl_query = sl_query
    RunMacro("Fixed OD Assignment", opts)
    ShowMessage("Fixed OD Assignment Complete")
  enditem
  Button 20, same Prompt: "Quit" do
    Return()
  enditem
  Button 28, same Prompt: "Help" do
    ShowMessage(
      "This tool lets you evaluate a roadway project quickly by " +
      "borrowing demand info from a fully-converged scenario."
    )
  enditem
enddbox

/*

*/

Macro "Fixed OD Assignment" (MacroOpts)

    ref_scen_dir = MacroOpts.ref_scen_dir
    sl_query = MacroOpts.sl_query

    mr = CreateObject("Model.Runtime")
    Args = mr.GetValues()
    ret = mr.RunStep("Create Initial Output Files", {Silent: "true"})
    if !ret then Throw("Fixed OD: 'Create Initial Output Files' failed")
    ret = mr.RunStep("Network Calculators", {Silent: "true"})
    if !ret then Throw("Fixed OD: 'Network Calculators' failed")
    RunMacro("Copy Files for Fixed OD", Args, ref_scen_dir)

    // Run assignments
    Args.sl_query = sl_query
    periods = Args.periods
    for period in periods do
        RunMacro("Run Roadway Assignment", Args, {period: period})
    end

    // Run summary macros of interest
    RunMacro("Load Link Layer", Args)
    RunMacro("Calculate Daily Fields", Args)
    RunMacro("Create Count Difference Map", Args)
    RunMacro("Count PRMSEs", Args)
    RunMacro("VOC Maps", Args)
    RunMacro("Speed Maps", Args)
    RunMacro("Summarize Links", Args)
    RunMacro("VMT_Delay Summary", Args)
endmacro

/*

*/

Macro "Copy Files for Fixed OD" (Args, ref_scen_dir)

    from_dir = ref_scen_dir
    to_dir = Args.[Scenario Folder]
    periods = Args.periods

    // OD matrices
    from_od_dir = from_dir + "/output/assignment/roadway"
    to_od_dir = to_dir + "/output/assignment/roadway/"
    for period in periods do
        from_file = from_od_dir + "/od_veh_trips_" + period + ".mtx"
        to_file = to_od_dir + "/od_veh_trips_" + period + ".mtx"
        CopyFile(from_file, to_file)
    end
endmacro

/*
Run the fixed OD tool for multiple scenarios
*/
Macro "Open FixedOD Multiple Projects Dbox" (Args)
	RunDbox("FixedOD Multiple Projects", Args)
endmacro
dBox "FixedOD Multiple Projects" (Args) center, center, 50, 12 Title: "Fixed OD Multiple Projects" Help: "test" toolbox

  init do
    static ref_scen_dir, sl_query, proj_list, add_rem_int, add_or_remove
    if add_rem_int = null then add_rem_int = 1
    if add_or_remove = null then add_or_remove = "add"
    scen_dir = Args.[Scenarios Folder]
  enditem

  close do
    return()
  enditem

  Text 15, after, 15 Prompt: "Reference Scenario:" Variable: "(current scenario)"

  Edit Text 15, 2, 15 Prompt: "Project List:" Variable: proj_list
  Button after, same, 5, 1 Prompt: "..." do
    on error, escape goto skip2
    proj_list = ChooseFile({{"CSV (*.csv)", "*.csv"}}, "Choose Project List", {"Initial Directory": scen_dir})
    skip2:
    on error default
  enditem
  Button after, same, 3, 1 Prompt: "?" do
    ShowMessage(
      "The project list should be a CSV file with a single column of project IDs " +
      "to be analyzed.\n" + 
      "For each project in the list, a new scenario will be created that includes " +
      "all projects in the reference scenario plus the single extra project id.\n" +
      "Do not include projects that are already in the reference scenario."
    )
  enditem

  Edit Text 15, 4, 15 Prompt: "Select Link Query:" Variable: sl_query
  Button after, same, 5, 1 Prompt: "..." do
    on error, escape goto skip3
    sl_query = ChooseFile({{"Query (*.qry)", "*.qry"}}, "Choose Select Link Query", {"Initial Directory": scen_dir})
    skip3:
    on error default
  enditem
  Text after, same, 10 Variable: "(optional)"

  Radio List "add_or_remove" 15, 6, 15, 2 Prompt: "Add or Remove Projects?" Variable: add_rem_int
    Radio Button "add" 15, 7 Prompt: "Add" do
      add_or_remove = "add"
    enditem
    Radio Button "remove" 15, 8 Prompt: "Remove" do
      add_or_remove = "remove"
    enditem
  Button 38, 6, 3, 1 Prompt: "?" do
    ShowMessage(
      "Should the projects in the project list be removed from the " + 
      "reference scenario or added?"
    )
  enditem

  Button 12, 10 Prompt: "Run" do
    opts.sl_query = sl_query
    opts.proj_list = proj_list
    opts.add_or_remove = add_or_remove
    RunMacro("FixedOD Multiple Projects", opts)
    ShowMessage("FixedOD Multiple Projects Complete")
  enditem
  Button 20, same Prompt: "Quit" do
    Return()
  enditem
  Button 28, same Prompt: "Help" do
    ShowMessage(
      "This tool runs the FixedOD utility for multiple projects.\n" + 
      "It requires one fully-run scenario and then a project list of " + 
      "projects to analyze.\n" + 
      "A scenario will be created for each project in that list and the " +
      "FixedOD utility will be run for each of them."
    )
  enditem
enddbox

/*

*/

Macro "FixedOD Multiple Projects" (MacroOpts)

    proj_list = MacroOpts.proj_list

    // Get the reference scenario name/dir and save it
    mr = CreateObject("Model.Runtime")
    {, ref_scen_name} = mr.GetScenario()
    ref_scen_name = mr.GetScenarioName(ref_scen_name)
    MacroOpts.ref_scen_name = ref_scen_name
    Args = mr.GetValues()
    MacroOpts.ref_scen_dir = Args.[Scenario Folder]
    mr = null

    proj_tbl = CreateObject("Table", proj_list)
    data = proj_tbl.GetDataVectors()
    // for each row in the project list
    for i = 1 to data[1][2].length do
      // create an array of all project IDs in that row
      for j = 1 to data.length do
        proj_id = data[j][2][i]
        if TypeOf(proj_id) = "null" then continue
        if TypeOf(proj_id) <> "string" then proj_id = String(proj_id)
        proj_ids = proj_ids + {proj_id}
      end
      
      MacroOpts.proj_ids = proj_ids
      RunMacro("Create FixedOD Project Scenario", MacroOpts)
      RunMacro("Fixed OD Assignment", MacroOpts)
      // Remove the scenario from the flowchart
      mr = CreateObject("Model.Runtime")
      {, new_scen_name} = mr.GetScenario()
      mr.DeleteScenario(new_scen_name)
      mr.SetScenario(ref_scen_name)
    end
endmacro

/*

*/

Macro "Create FixedOD Project Scenario" (MacroOpts)

    ref_scen_dir = MacroOpts.ref_scen_dir
    ref_scen_name = MacroOpts.ref_scen_name
    proj_ids = MacroOpts.proj_ids
    add_or_remove = MacroOpts.add_or_remove
    
    // create the directory and copy project lists over
    scen_name_suffix = proj_ids[1]
    if add_or_remove = "add"
      then new_scen_dir = ref_scen_dir + "_plus_" + scen_name_suffix
      else new_scen_dir = ref_scen_dir + "_minus_" + scen_name_suffix
    // Multiple rows could start with the same project ID and include
    // different projects. If the directory already exists, add a number
    // to the end of the directory name to make it unique. 
    if GetDirectoryInfo(new_scen_dir, "All") <> null then do
      for i = 1 to 1000 do
        temp = new_scen_dir + "_" + String(i)
        if GetDirectoryInfo(temp, "All") = null then do
          new_scen_dir = temp
          break
        end
      end
    end
    RunMacro("Create Directory", new_scen_dir)
    parts = ParseString(new_scen_dir, "\\")
    new_scen_name = parts[parts.length]
    CopyFile(
      ref_scen_dir + "\\RoadwayProjectList.csv",
      new_scen_dir + "\\RoadwayProjectList.csv"
    )
    CopyFile(
      ref_scen_dir + "\\TransitProjectList.csv",
      new_scen_dir + "\\TransitProjectList.csv"
    )

    csv_file = new_scen_dir + "\\RoadwayProjectList.csv"
    tbl = CreateObject("Table", csv_file)
    ids = tbl.ProjID
    if TypeOf(ids) <> "null" and TypeOf(ids[1]) <> "string" then ids = String(ids)
    tbl = null
    if add_or_remove = "add" then do
      for proj_id in proj_ids do
        // Check if this project ID is already in the list
        if ids.position(proj_id) > 0 then Throw(
          "Project ID to add ('" + proj_id + "') is already in the project list" + 
          " and so is in the original scenario."
        )
        tbl = null

        // Add this project ID to the end of the roadway project list
        file = OpenFile(csv_file, "a")
        WriteLine(file, proj_id)
        CloseFile(file)
      end
    end else do
      // Remove the project ID
      // tbl = CreateObject("Table", file)
      // ids = tbl.ProjID
      // tbl = null
      for proj_id in proj_ids do
        if ids.position(proj_id) = 0 then Throw(
          "Project ID to remove ('" + proj_id + "') not found in project list\n" +
          "(and so isn't in original scenario)."
        )
      end
      file = OpenFile(csv_file, "w")
      WriteLine(file, "ProjID")
      for id in ids do
        if proj_ids.position(id) = 0 then WriteLine(file, id)
      end
      CloseFile(file)
    end

    // Create the scenario in the flowchart
    mr = CreateObject("Model.Runtime")
    parentName = ref_scen_name
    new_scen_name_full = mr.CreateScenario(parentName, new_scen_name, )
    mr.SetScenario(new_scen_name_full)
    mr.SetScenarioValues({"Scenario Folder": new_scen_dir})
    mr.SetScenario(new_scen_name_full)

    // Call the standard TRMG2 create scenario macro
    ret = mr.RunCode("Create Scenario", mr.GetValues())
endmacro