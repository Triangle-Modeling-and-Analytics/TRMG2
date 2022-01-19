/*
Summarizes the results of the disaggregate models in order to transition to
the aggregate components.
*/

Macro "Aggregation to Zones" (Args)

    RunMacro("Aggregate HB Moto Trips", Args)
    return(1)
endmacro

/*
Collapses the person-level home-based trip productions by trip type, market
segment, and TAZ. Appends to the SE Data. Motorized trips only.
*/

Macro "Aggregate HB Moto Trips" (Args)

    hh_file = Args.Households
    per_file = Args.Persons
    se_file = Args.SE

    // Join with person data and aggregate trips
    hh_vw = OpenTable("hh", "FFB", {hh_file})
    per_vw = OpenTable("persons", "FFB", {per_file})
    jv = JoinViews("jv", per_vw + ".HouseholdID", hh_vw + ".HouseholdID", )
    df = CreateObject("df", jv)
    CloseView(jv)
    df.rename("persons_market_segment", "market_segment")
    df.group_by({"ZoneID", "market_segment"})
    trip_types = RunMacro("Get HB Trip Types", Args)
    field_names = V2A(A2V(trip_types) + "_m")
    df.summarize(field_names, "sum")
    names = df.colnames()
    for name in names do
        if Left(name, 4) = "sum_" then do
            new_name = Substitute(name, "sum_", "", 1)
            new_name = Substitute(new_name, "_m", "", 1)
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