/*
The purpose of this tool to is allow supply side changes to be evaluated
quickly without affecting the demand (OD matrix).
*/
Macro "Open Fixed OD Dbox" (Args)
	RunDbox("FixedOD", Args)
endmacro
dBox "FixedOD" (Args) center, center, 50, 8 Title: "Fixed OD Assignment" Help: "test" toolbox

  init do
    static full_scen_dir, sl_query
    scen_dir = Args.[Scenarios Folder]
  enditem

  close do
    return()
  enditem

  Edit Text 15, 1, 15 Prompt: "Completed Scenario:" Variable: full_scen_dir
  Button after, same, 5, 1 Prompt: "..." do
    on error, escape goto skip1
    full_scen_dir = ChooseDirectory("Choose Full Scenario Folder", {"Initial Directory": scen_dir})
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
    if full_scen_dir = Args.[Scenario Folder] then do
        Throw("The full scenario and current scenario cannot be the same")
        return()
    end
    opts.full_scen_dir = full_scen_dir
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

    full_scen_dir = MacroOpts.full_scen_dir
    sl_query = MacroOpts.sl_query

    mr = CreateObject("Model.Runtime")
    Args = mr.GetValues()
    ret = mr.RunStep("Create Initial Output Files", {Silent: "true"})
    if !ret then Throw("Fixed OD: 'Create Initial Output Files' failed")
    ret = mr.RunStep("Network Calculators", {Silent: "true"})
    if !ret then Throw("Fixed OD: 'Network Calculators' failed")
    RunMacro("Copy Files for Fixed OD", Args, full_scen_dir)

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
endmacro

/*

*/

Macro "Copy Files for Fixed OD" (Args, full_scen_dir)

    from_dir = full_scen_dir
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
dBox "FixedOD Multiple Projects" (Args) center, center, 50, 8 Title: "Fixed OD Multiple Projects" Help: "test" toolbox

  init do
    static full_scen_dir, sl_query, proj_list
    scen_dir = Args.[Scenarios Folder]
  enditem

  close do
    return()
  enditem

  Text 15, after, 15 Prompt: "Completed Scenario:" Variable: "(current scenario)"

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
      "all projects in the completed scenario plus the single extra project id.\n" +
      "Do not include projects that are already in the completed scenario."
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

  Button 12, 6.5 Prompt: "Run" do
    opts.sl_query = sl_query
    opts.proj_list = proj_list
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

    // Get the base/completed scenario name/dir and save it
    mr = CreateObject("Model.Runtime")
    {, full_scen_name} = mr.GetScenario()
    full_scen_name = mr.GetScenarioName(full_scen_name)
    MacroOpts.full_scen_name = full_scen_name
    Args = mr.GetValues()
    MacroOpts.full_scen_dir = Args.[Scenario Folder]
    mr = null

    proj_tbl = CreateObject("Table", proj_list)
    proj_ids = proj_tbl.ProjID
    if proj_ids.type <> "string" then proj_ids = String(proj_ids)

    for proj_id in proj_ids do
      MacroOpts.proj_id = proj_id
      RunMacro("Create FixedOD Project Scenario", MacroOpts)
      RunMacro("Fixed OD Assignment", MacroOpts)

      // Remove the scenario from the flowchart
      mr = CreateObject("Model.Runtime")
      {, new_scen_name} = mr.GetScenario()
      // mr.SetScenario(new_scen_name)
      mr.DeleteScenario(new_scen_name)
      mr.SetScenario(full_scen_name)
    end

endmacro

/*

*/

Macro "Create FixedOD Project Scenario" (MacroOpts)

    full_scen_dir = MacroOpts.full_scen_dir
    full_scen_name = MacroOpts.full_scen_name
    proj_list = MacroOpts.proj_list
    proj_id = MacroOpts.proj_id
    
    // create the directory and copy project lists over
    new_scen_dir = full_scen_dir + "_" + proj_id
    RunMacro("Create Directory", new_scen_dir)
    parts = ParseString(new_scen_dir, "\\")
    new_scen_name = parts[parts.length]
    CopyFile(
      full_scen_dir + "\\RoadwayProjectList.csv",
      new_scen_dir + "\\RoadwayProjectList.csv"
    )
    CopyFile(
      full_scen_dir + "\\TransitProjectList.csv",
      new_scen_dir + "\\TransitProjectList.csv"
    )
    // Append this project ID to the end of the roadway project list
    file = OpenFile(new_scen_dir + "\\RoadwayProjectList.csv", "a")
    WriteLine(file, proj_id)
    CloseFile(file)

    // Create the scenario in the flowchart
    mr = CreateObject("Model.Runtime")
    parentName = full_scen_name
    new_scen_name_full = mr.CreateScenario(parentName, new_scen_name, )
    mr.SetScenario(new_scen_name_full)
    mr.SetScenarioValues({"Scenario Folder": new_scen_dir})
    mr.SetScenario(new_scen_name_full)

    // Call the standard TRMG2 create scenario macro
    ret = mr.RunCode("Create Scenario", mr.GetValues())
endmacro