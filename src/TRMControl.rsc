Macro "TRM"
    on escape, error, notfound do
        ErrorMsg = GetLastError()
        ShowMessage(ErrorMsg)
        ret_value = 0
        goto quit
    end

    // **************** Start of Parameter definitions ******************
    scen_dir = "C:\\projects\\TRM\\Repo\\scenarios\\base_2016"
    Args = null
    // *********** Folders *************
    Args.[Scenario Folder] = scen_dir
    Args.[Input Folder] = scen_dir + "\\input"      // This parameter will be a derived parameter in the flowchart
    Args.[Output Folder] = scen_dir + "\\output"    // This parameter will be a derived parameter in the flowchart
    
    // *********** SED Disaggregation parameters *************
    // Input
    Args.TAZDB = Args.[Input Folder] + "\\tazs\\master_tazs.dbd"
    Args.SEData = Args.[Input Folder] + "\\se_data\\se_2016.bin"
    Args.IncomeCurves = Args.[Input Folder] + "\\resident\\disagg_model\\income_curves.csv"
    Args.SizeCurves = Args.[Input Folder] + "\\resident\\disagg_model\\size_curves.csv"
    Args.WorkerCurves = Args.[Input Folder] + "\\resident\\disagg_model\\worker_curves.csv"
    Args.RegionalMedianIncome = 65317
    // Output
    Args.SEDMarginals = Args.[Output Folder] + "\\resident\\disagg_model\\SEDMarginals.bin"

    // *********** Population Synthesis Parameters *************
    // Input
    Args.[PUMS HH Seed] = Args.[Input Folder] + "\\resident\\population_synthesis\\HHSeed_PUMS_TRM.bin"
    Args.[PUMS Person Seed] = Args.[Input Folder] + "\\resident\\population_synthesis\\PersonSeed_PUMS_TRM.bin"
    // Output
    Args.[Synthesized HHs] = Args.[Output Folder] + "\\resident\\population_synthesis\\Synthesized_HHs.bin"
    Args.[Synthesized Persons] = Args.[Output Folder] + "\\resident\\population_synthesis\\Synthesized_Persons.bin"
    Args.[Synthesized Tabulations] = Args.[Output Folder] + "\\resident\\population_synthesis\\Synthesized_Tabulations.bin"


    // **************** Create Output Folders ************************
    folders = {Args.[Output Folder], Args.[Output Folder] + "\\resident", 
               Args.[Output Folder] + "\\resident\\disagg_model", Args.[Output Folder] + "\\resident\\population_synthesis"}
    for f in folders do
        on error do
            goto skipcreate
        end
        CreateDirectory(f)
      skipcreate:
        on error default
    end


    // **************** Run Macros ************************************
    // Run Macro to disaggegate curves
    ret_value = RunMacro("DisaggregateSED", Args)
    if !ret_value then
        Throw("'DisaggregateSED' macro failed")
    
    // Run Macro for population synthesis
    ret_value = RunMacro("Population Synthesis", Args)
    if !ret_value then
        Throw("'Population Synthesis' macro failed")

    // Run Post Process Macro for population synthesis
    ret_value = RunMacro("PopSynth Post Process", Args)
    if !ret_value then
        Throw("'PopSynth Post Process' macro failed")

 quit:
    on error, notfound, escape default
    if !ret_value then do
        if ErrorMsg <> null then
            AppendToLogFile(0, ErrorMsg)
    end
    ShowMessage(String(ret_value))
    Return(ret_value)

endMacro
