/*
Summarizes the results of the disaggregate models in order to transition to
the aggregate components.
*/

Macro "Aggregation" (Args)

    RunMacro("Aggregate HB Trips by Market Segment", Args)
    return(1)
endmacro

/*
Collapses the person-level home-based trip productions by trip type, market
segment, and TAZ. Appends to the SE Data.
*/

Macro "Aggregate HB Trips by Market Segment" (Args)

    hh_file = Args.Households
    per_file = Args.Persons
    se_file = Args.SE

    // Classify households by market segment
    hh_vw = OpenTable("hh", "FFB", {hh_file})
    a_fields = {
        {"market_segment", "Character", 10, , , , , "Aggregate market segment this household belongs to"}
    }
    RunMacro("Add Fields", {view: hh_vw, a_fields: a_fields})
    input = GetDataVectors(hh_vw + "|", {"HHSize", "IncomeCategory", "Autos"}, {OptArray: TRUE})
    v_sufficient = if input.Autos = 0 then "v0"
        else if input.Autos < input.HHSize then "vi"
        else "vs"
    v_income = if input.IncomeCategory <= 2 then "il" else "ih"
    v_market = if v_sufficient = "v0"
        then "v0"
        else v_income + v_sufficient
    SetDataVector(hh_vw + "|", "market_segment", v_market, )

    // Join with person data and aggregate trips
    per_vw = OpenTable("persons", "FFB", {per_file})
    jv = JoinViews("jv", per_vw + ".HouseholdID", hh_vw + ".HouseholdID", )
    df = CreateObject("df", jv)
    CloseView(jv)
    df.group_by({"ZoneID", "market_segment"})
    trip_types = RunMacro("Get HB Trip Types", Args)
    df.summarize(trip_types, "sum")
    names = df.colnames()
    for name in names do
        if Left(name, 4) = "sum_" then do
            new_name = Substitute(name, "sum_", "", 1)
            df.rename(name, new_name)
        end
    end
    CloseView(per_vw)
    CloseView(hh_vw)

    // Re-org data and append to SE    
    se_df = CreateObject("df", se_file)
    se_df.select("TAZ")
    segments = {"v0", "ilvi", "ihvi", "ilvs", "ihvs"}
    for segment in segments do
        df2 = df.copy()
        df2.filter("market_segment = '" + segment + "'")
        df2.remove("market_segment")
        names = A2V(df2.colnames())
        names = names + "_" + segment
        names[1] = "ZoneID"
        df2.colnames({new_names: names})
        se_df.left_join(df2, "TAZ", "ZoneID")
        for n = 2 to names.length do
            col = names[n]
            se_df.tbl.(col) = nz(se_df.tbl.(col))
        end
    end

    // For trip types other than W_HB_W_All, collapse market segments
    for trip_type in trip_types do
        if Lower(trip_type) = "w_hb_w_all" then continue
        for segment in segments do
            if segment = "v0" then continue
            if Position(segment, "vi") > 0 
                then new_segment = "vi"
                else new_segment = "vs"

            from_field = trip_type + "_" + segment
            to_field = trip_type + "_" + new_segment
            se_df.tbl.(to_field) = nz(se_df.tbl.(to_field)) + se_df.tbl.(from_field)
            se_df.remove(from_field)
        end
    end
    se_df.remove("TAZ")
    se_df.update_bin(se_file)
endmacro