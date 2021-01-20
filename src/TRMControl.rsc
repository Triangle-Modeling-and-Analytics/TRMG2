Macro "TRM"
    // **************** Start of Parameter definitions ******************
    scen_dir = "C:\\projects\\TRM\\Repo\\scenarios\\base_2016"
    Args = null
    // *********** Folders *************
    Args.[Scenario Folder] = scen_dir
    Args.[Input Folder] = scen_dir + "\\input"      // This parameter will be a derived parameter in the flowchart
    Args.[Output Folder] = scen_dir + "\\output"    // This parameter will be a derived parameter in the flowchart
    
    // *********** Create Output Folders. This will also go into the flowchart code ******

    
    // *********** SED Disaggregation *************
    // Input
    Args.SEData = Args.[Input Folder] + "\\se_data\\se_2016.bin"
    Args.IncomeCurves = Args.[Input Folder] + "\\resident\\disagg_model\\income_curves.csv"
    Args.SizeCurves = Args.[Input Folder] + "\\resident\\disagg_model\\size_curves.csv"
    Args.WorkerCurves = Args.[Input Folder] + "\\resident\\disagg_model\\worker_curves.csv"
    Args.RegionalMedianIncome = 65317
    // Output
    Args.SEDMarginals = Args.[Output Folder] + "\\resident\\disagg_model\\SEDMarginals.bin"

    // *********** Population Synthesis *************
    // Input
    Args.[PUMS HH Seed] = Args.[Input Folder] + "\\resident\\population_synthesis\\HHSeed_PUMS_TRM.bin"
    Args.[PUMS Person Seed] = Args.[Input Folder] + "\\resident\\population_synthesis\\PersonSeed_PUMS_TRM.bin"
    // Output
    Args.[Synthesized HHs] = Args.[Output Folder] + "\\resident\\population_synthesis\\Synthesized_HHs.bin"
    Args.[Synthesized Persons] = Args.[Output Folder] + "\\resident\\population_synthesis\\Synthesized_Persons.bin"
    Args.[Synthesized Tabulations] = Args.[Output Folder] + "\\resident\\population_synthesis\\Synthesized_Tabulations.bin"
    
    // **************** End of Parameter definitions ******************
    
    // Run Macro to disaggegate curves
    ret = RunMacro("DisaggregateSED", Args)
    
    // Run Macro for population synthesis
    ret = RunMacro("Population Synthesis", Args)

    // Run Post Process Macro for population synthesis
    ret = RunMacro("PopSynth Post Process", Args)

endMacro
