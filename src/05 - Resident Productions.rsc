/*

*/

Macro "Home-based Productions" (Args)
    RunMacro("Create Production Features", Args)
    RunMacro("Apply Production Rates", Args)
    RunMacro("Classify Households by Market Segment", Args)
    RunMacro("Apply Calibration Factors", Args)

    return(1)
endmacro

/*

*/

Macro "Create Production Features" (Args)

    hh_file = Args.Households
    per_file = Args.Persons
    se_file = Args.SE

    hh_vw = OpenTable("hh", "FFB", {hh_file})
    per_vw = OpenTable("per", "FFB", {per_file})
    se_vw = OpenTable("per", "FFB", {se_file})
    per_fields =  {
        {"HHTAZ", "Integer", 10, ,,,, "Home TAZ"},
        {"is_senior", "Integer", 10, ,,,, "Is the person a senior (>= 65)?"},
        {"is_child", "Integer", 10, ,,,, "Is the person a child (< 18)?"},
        {"is_worker", "Integer", 10, ,,,, "Is the person a worker?"},
        {"single_parent", "Integer", 10, ,,,, "Is the person a single parent?"},
        {"retired_hh", "Integer", 10, ,,,, "If the household contains only retirees"},
        {"per_inc", "Real", 10, 2,,,, "Per-capita income (hh income / hh size)"},
        {"oth_ppl", "Integer", 10, ,,,, "Number of other people in the household"},
        {"oth_kids", "Integer", 10, ,,,, "Number of other kids in the household"},
        {"oth_wrkr", "Integer", 10, ,,,, "Number of other workers in the household"},
        {"oth_senior", "Integer", 10, ,,,, "Number of other seniors in the household"},
        {"g_access", "Real", 10, 2,,,, "General accessibility of home zone"},
        {"n_access", "Real", 10, 2,,,, "Nearby accessibility of home zone"},
        {"e_access", "Real", 10, 2,,,, "Employment accessibility of home zone"},
        {"w_access", "Real", 10, 2,,,, "Walk accessibility of home zone"}
    }
    RunMacro("Add Fields", {view: per_vw, a_fields: per_fields})
    {, hh_specs} = RunMacro("Get Fields", {view_name: hh_vw})
    {, per_specs} = RunMacro("Get Fields", {view_name: per_vw})
    {, se_specs} = RunMacro("Get Fields", {view_name: se_vw})

    temp_vw = JoinViews("per+hh", per_specs.HouseholdID, hh_specs.HouseholdID, )
    {, temp_specs} = RunMacro("Get Fields", {view_name: temp_vw})
    jv = JoinViews("per+hh+se", temp_specs.ZoneID, se_specs.TAZ, )
    CloseView(temp_vw)
    {v_taz, v_size, v_workers, v_inc, v_kids, v_seniors, v_workers,  
    v_emp_status, v_age, v_ga, v_na, v_ea, v_wa} = GetDataVectors(jv + "|", {
        hh_specs.ZoneID,
        hh_specs.HHSize,
        hh_specs.NumberWorkers,
        hh_specs.HHInc,
        hh_specs.HHKids,
        hh_specs.HHSeniors,
        hh_specs.HHWorkers,
        per_specs.EmploymentStatus,
        per_specs.Age,
        se_specs.access_general_sov,
        se_specs.access_nearby_sov,
        se_specs.access_employment_sov,
        se_specs.access_walk
    },)

    data.(per_specs.HHTAZ) = v_taz
    data.(per_specs.is_senior) = if v_age >= 65 then 1 else 0
    data.(per_specs.is_child) = if v_age < 18 then 1 else 0
    data.(per_specs.is_worker) = if v_emp_status = 1 or v_emp_status = 2 or v_emp_status = 4 or v_emp_status = 5
        then 1
        else 0
    v_num_adults = v_size - v_kids
    data.(per_specs.single_parent) = if data.(per_specs.is_child) = 0 and v_num_adults = 1 and v_kids > 0
        then 1
        else 0
    data.(per_specs.per_inc) = v_inc / v_size
    data.(per_specs.retired_hh) = if v_size = v_seniors and v_workers = 0 then 1 else 0
    data.(per_specs.oth_ppl) = v_size - 1
    data.(per_specs.oth_kids) = v_kids - data.(per_specs.is_child)
    data.(per_specs.oth_wrkr) = v_workers - data.(per_specs.is_worker)
    data.(per_specs.oth_senior) = v_seniors - data.(per_specs.is_senior)
    data.(per_specs.g_access) = v_ga
    data.(per_specs.n_access) = v_na
    data.(per_specs.e_access) = v_ea
    data.(per_specs.w_access) = v_wa
    SetDataVectors(jv + "|", data, )
    
    CloseView(jv)
    CloseView(hh_vw)
    CloseView(per_vw)
    CloseView(se_vw)
endmacro

/*

*/

Macro "Apply Production Rates" (Args)

    per_file = Args.Persons
    rate_file = Args.ProdRates
    RunMacro("Apply Rates with Queries", {per_file: per_file, rate_csv: rate_file})
endmacro

/*
A generic utility function that can apply decision trees that have been
converted to a list of GISDK queries. Currently only used by the production
model, so I'm just leaving it here.
*/

Macro "Apply Rates with Queries" (MacroOpts)

    per_file = MacroOpts.per_file
    rate_csv = MacroOpts.rate_csv

    view = OpenTable("per", "FFB", {per_file})

    // Get rates
    rate_vw = OpenTable("rate_vw", "CSV", {rate_csv})
    {v_type, v_query, v_rate} = GetDataVectors(rate_vw + "|", {
        "trip_type", "rule", "rate"
    },)
    CloseView(rate_vw)

    // Add fields
    v_unique_types = SortVector(v_type, {Unique: true})
    for field in v_unique_types do
        a_fields = a_fields + {{field, "Real", 10, 2,,,, "Resident productions"}}
    end
    RunMacro("Add Fields", {view: view, a_fields: a_fields})

    // Loop over queries/rates
    SetView(view)
    for i = 1 to v_type.length do
        type = v_type[i]
        query = v_query[i]
        rate = v_rate[i]

        if i = 1 or type <> v_type[i - 1] then expression = "if (" + query + ") then " + String(rate)
        else expression = expression + " else if (" + query + ") then " + String(rate)
        
        if i = v_type.length or type <> v_type[i + 1] then do
            e_field = CreateExpression(view, "expr", expression, {Type: "Real"})
            data.(type) = GetDataVector(view + "|", e_field, )
            e_spec = GetFieldFullSpec(view, e_field)
            DestroyExpression(e_spec)
        end
    end
    SetDataVectors(view + "|", data, )

    CloseView(view)
endmacro

/*

*/

Macro "Classify Households by Market Segment" (Args)

    hh_file = Args.Households
    per_file = Args.Persons
    se_file = Args.SE

    // Classify households by market segment
    hh_vw = OpenTable("hh", "FFB", {hh_file})
    a_fields = {
        {"market_segment", "Character", 10, , , , , "Aggregate market segment this household belongs to"}
    }
    RunMacro("Add Fields", {view: hh_vw, a_fields: a_fields})
    input = GetDataVectors(hh_vw + "|", {"HHSize", "IncomeCategory", "HHKids", "Autos"}, {OptArray: TRUE})
    v_adults = input.HHSize - input.HHKids
    v_sufficient = if input.Autos = 0 then "v0"
        else if input.Autos < v_adults then "vi"
        else "vs"
    v_income = if input.IncomeCategory <= 2 then "il" else "ih"
    v_market = if v_sufficient = "v0"
        then "v0"
        else v_income + v_sufficient
    SetDataVector(hh_vw + "|", "market_segment", v_market, )

    // Copy this segment info to the person table
    per_vw = OpenTable("persons", "FFB", {per_file})
    a_fields = {
        {"market_segment", "Character", 10, , , , , "Aggregate market segment of household this person lives in"}
    }
    RunMacro("Add Fields", {view: per_vw, a_fields: a_fields})
    jv = JoinViews("jv", per_vw + ".HouseholdID", hh_vw + ".HouseholdID", )
    v = GetDataVector(jv + "|", hh_vw + ".market_segment", )
    SetDataVector(jv + "|", per_vw + ".market_segment", v, )
    CloseView(jv)
    CloseView(hh_vw)
    CloseView(per_vw)
endmacro

/*
Apply calibration factors by trip type
*/

Macro "Apply Calibration Factors" (Args)
    
    per_file = Args.Persons
    factor_file = Args.ProdCalibFactors
    
    per_vw = OpenTable("per", "FFB", {per_file})

    factor_vw = OpenTable("factor", "CSV", {factor_file})
    segments = GetDataVector(factor_vw + "|", "segment", )
    unique_segments = SortVector(segments, {Unique: "true"})

    for segment in unique_segments do

        SetView(factor_vw)
        SelectByQuery("sel", "several", "Select * where segment = '" + segment + "'")
        trip_types = GetDataVector(factor_vw + "|sel", "trip_type", )
        factors = GetDataVector(factor_vw + "|sel", "factor", )

        SetView(per_vw)
        query = "Select * where market_segment = '"
        if segment = "v0" then query = query + segment + "'"
        else query = query + "ih" + segment + "' or market_segment = '" + "il" + segment + "'"
        n = SelectByQuery("sel", "several", query)
        if n = 0 then Throw("no records found")
    
        output = null
        for i = 1 to trip_types.length do
            trip_type = trip_types[i]
            factor = factors[i]

            v = GetDataVector(per_vw + "|sel", trip_type, )
            output.(trip_type) = v * factor
        end
        SetDataVectors(per_vw + "|sel", output, )
    end

    CloseView(per_vw)
    CloseView(factor_vw)
endmacro