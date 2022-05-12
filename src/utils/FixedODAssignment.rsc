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