/*

*/

Macro "NonResident DC and MC" (Args)

    RunMacro("CV Gravity", Args)
    RunMacro("Airport Mode Choice", Args)
    RunMacro("Airport Separate Auto and Transit", Args)
    RunMacro("Airport Directionality", Args)
    RunMacro("University Gravity", Args)
    RunMacro("University Combine Matrix", Args)
    RunMacro("University Directionality", Args)
    RunMacro("University MC Probabilities", Args)
    RunMacro("University Mode Choice", Args)
    return(1)
endmacro