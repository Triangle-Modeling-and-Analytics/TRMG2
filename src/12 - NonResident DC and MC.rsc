/*

*/

Macro "NonResident DC and MC" (Args)

    RunMacro("CV Gravity", Args)
    RunMacro("Airport Mode Choice", Args)
    RunMacro("Airport Separate Auto and Transit", Args)
    RunMacro("Airport Directionality", Args)
    return(1)
endmacro