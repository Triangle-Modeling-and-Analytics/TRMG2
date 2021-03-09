/*

*/

Macro "Resident Productions" (Args)

    RunMacro("Create Production Features", Args)
    RunMacro("Apply Production Rates", Args)

    return(1)
endmacro

/*

*/

Macro "Create Production Features" (Args)

    hh_file = Args.[Synthesized HHs]
    per_file = Args.[Synthesized Persons]
    se_file = Args.SE

    hh_vw = OpenTable("hh", "FFB", {hh_file})
    per_vw = OpenTable("per", "FFB", {per_file})
    se_vw = OpenTable("per", "FFB", {se_file})
    per_fields =  {
        {"is_senior", "Integer", 10, ,,,, "Is the person a senior (>= 65)?"},
        {"is_child", "Integer", 10, ,,,, "Is the person a child (< 18)?"},
        {"is_worker", "Integer", 10, ,,,, "Is the person a worker?"},
        {"retired_hh", "Integer", 10, ,,,, "If the household contains only retirees"},
        {"per_inc", "Real", 10, 2,,,, "Per-capita income (hh income / hh size)"},
        {"oth_ppl", "Integer", 10, ,,,, "Number of other people in the household"},
        {"oth_kids", "Integer", 10, ,,,, "Number of other kids in the household"},
        {"oth_wrkr", "Integer", 10, ,,,, "Number of other workers in the household"},
        {"g_access", "Real", 10, 2,,,, "General accessibility of home zone"},
        {"n_access", "Real", 10, 2,,,, "Nearby accessibility of home zone"},
        {"e_access", "Real", 10, 2,,,, "Employment accessibility of home zone"}
    }
    RunMacro("Add Fields", {view: per_vw, a_fields: per_fields})
    {, hh_specs} = RunMacro("Get Fields", {view_name: hh_vw})
    {, per_specs} = RunMacro("Get Fields", {view_name: per_vw})
    {, se_specs} = RunMacro("Get Fields", {view_name: se_vw})

    temp_vw = JoinViews("per+hh", per_specs.HouseholdID, hh_specs.HouseholdID, )
    {, temp_specs} = RunMacro("Get Fields", {view_name: temp_vw})
    jv = JoinViews("per+hh+se", temp_specs.ZoneID, se_specs.TAZ, )
    CloseView(temp_vw)
    {v_size, v_workers, v_inc, v_kids, v_seniors, v_workers,  
    v_emp_status, v_age, v_ga, v_na, v_ea} = GetDataVectors(jv + "|", {
        hh_specs.HHSize,
        hh_specs.NumberWorkers,
        hh_specs.HHInc,
        hh_specs.HHKids,
        hh_specs.HHSeniors,
        hh_specs.HHWorkers,
        per_specs.EmploymentStatus,
        per_specs.Age,
        se_specs.GeneralAccessibility_sov,
        se_specs.NearbyAccessibility_sov,
        se_specs.EmploymentAccessibility_sov
    },)

    data.(per_specs.is_senior) = if v_age >= 65 then 1 else 0
    data.(per_specs.is_child) = if v_age < 18 then 1 else 0
    data.(per_specs.is_worker) = if v_emp_status = 1 or v_emp_status = 2 or v_emp_status = 4 or v_emp_status = 5
        then 1
        else 0
    data.(per_specs.per_inc) = v_inc / v_size
    data.(per_specs.retired_hh) = if v_size = v_seniors and v_workers = 0 then 1 else 0
    data.(per_specs.oth_ppl) = v_size - 1
    data.(per_specs.oth_kids) = v_kids - data.(per_specs.is_child)
    data.(per_specs.oth_wrkr) = v_workers - data.(per_specs.is_worker)
    data.(per_specs.g_access) = v_ga
    data.(per_specs.n_access) = v_na
    data.(per_specs.e_access) = v_ea
    SetDataVectors(jv + "|", data, )
    CloseView(jv)
endmacro

/*

*/

Macro "Apply Production Rates" (Args)

    // hh_file = Args.[Synthesized HHs]
    // per_file = Args.[Synthesized Persons]
    // se_file = Args.SE

    // hh_vw = OpenTable("hh", "FFB", {hh_file})
    // per_vw = OpenTable("per", "FFB", {per_file})
    // se_vw = OpenTable("per", "FFB", {se_file})
    // {, hh_specs} = RunMacro("Get Fields", {view_name: hh_vw})
    // {, per_specs} = RunMacro("Get Fields", {view_name: per_vw})
    // {, se_specs} = RunMacro("Get Fields", {view_name: se_vw})
endmacro