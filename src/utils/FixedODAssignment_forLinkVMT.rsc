/*
This tool is essentially the same as Fixed OD assignment, with the exception of requiring a select link query.
It's designed for calculating link VMT for TIA Site Analysis.
*/
Macro "Open Select Link Dbox" (Args)
	RunDbox("SelectLink", Args)
endmacro
dBox "SelectLink" (Args) center, center, 50, 8 Title: "Select Link Analysis" Help: "test" toolbox

  init do
    static sl_query
    scen_dir = Args.[Scenarios Folder]
  enditem

  close do
    return()
  enditem

  Text 15, 1, 15 Prompt: "Selected Scenario:" Variable: "(current scenario)"

  Edit Text same, after, 15 Prompt: "Select Link Query:" Variable: sl_query
  Button after, same, 5, 1 Prompt: "..." do
    on error, escape goto skip2
    sl_query = ChooseFile({{"Query (*.qry)", "*.qry"}}, "Choose Select Link Query", {"Initial Directory": scen_dir})
    skip2:
    on error default
  enditem


  Button 12, 6.5 Prompt: "Run" do
    opts.sl_query = sl_query
    if sl_query = null then do
        Throw("The select link query cannot be empty.")
        return()
    end
    RunMacro("Fixed OD Assignment", opts)
    ShowMessage("Fixed OD Assignment Complete")
  enditem
  Button 20, same Prompt: "Quit" do
    Return()
  enditem
  Button 28, same Prompt: "Help" do
    ShowMessage(
      "This tool calculates link VMT going to the study zone(s)." +
      " Before running this tool, build the link query using the" +
      " incoming direction of centroid connectors of the study zone(s)."+
      "Then select the completed project scenario using dropdown menu." 

    )
  enditem
enddbox

/*

*/

Macro "Fixed OD Assignment" (MacroOpts)

    sl_query = MacroOpts.sl_query
    mr = CreateObject("Model.Runtime")
    Args = mr.GetValues()
    
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

