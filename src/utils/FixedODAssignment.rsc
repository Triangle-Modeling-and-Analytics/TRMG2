/*
The purpose of this tool to is allow supply side changes to be evaluated
quickly without affecting the demand (OD matrix).
*/
Macro "Open Fixed OD Dbox" (Args)
	RunDbox("FixedOD", Args)
endmacro
dBox "FixedOD" (Args) center, center, 50, 8 Title: "Fixed OD Assignment" Help: "test" toolbox

  init do
    static full_scen_dir
    scen_dir = Args.[Scenarios Folder]
  enditem

  close do
    return()
  enditem

  Edit Text 15, 2, 15 Prompt: "Completed Scenario:" Variable: full_scen_dir
  Button after, same, 5, 1 Prompt: "..." do
    on error, escape goto skip1
    full_scen_dir = ChooseDirectory("Choose Full Scenario Folder", {"Initial Directory": scen_dir})
    skip1:
    on error default
  enditem

  Text 15, after, 15 Prompt: "New Scenario:" Variable: "(current scenario)"

  Button 8, 6 Prompt: "Run" do
    mr = CreateObject("Model.Runtime")
    Args = mr.GetValues()
    if full_scen_dir = Args.[Scenario Folder] then do
        Throw("The full scenario and current scenario cannot be the same")
        return()
    end
    RunMacro("Fixed OD Assignment", full_scen_dir)
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

Macro "Fixed OD Assignment" (full_scen_dir)

    mr = CreateObject("Model.Runtime")
    Args = mr.GetValues()
    // This flag is used to modify certain steps of the model.
    // For example, 
    Args.fixed_od = "true" // lets us skip transit net creation
    ret = mr.RunStep("Initial Processing", {Silent: "true"})
    if !ret then return()
    RunMacro("Copy Files for Fixed OD", Args, full_scen_dir)

    // Run assignments
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
    RunMacro("Summarize by FT and AT", Args)
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