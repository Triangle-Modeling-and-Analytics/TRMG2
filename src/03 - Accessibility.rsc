/*

*/

Macro "Accessibility" (Args)

    RunMacro("Calc Gini-Simpson Diversity Index", Args)
    RunMacro("Calc Intersection Approach Density", Args)
    RunMacro("Calc Percent of Zone Near Bus Stop", Args)

    return(1)
endmacro

/*

*/

Macro "Calc Gini-Simpson Diversity Index" (Args)

    se_file = Args.SE
    rate_file = Args.[GS Rates]

    rate_vw = OpenTable("rates", "CSV", {rate_file})
    {v_fields, v_rates} = GetDataVectors(
        rate_vw + "|",
        {"Field", "Value"},
    )
    CloseView(rate_vw)

    se_vw = OpenTable("se", "FFB", {se_file})
    a_fields = {
        {"GSAttractions", "Real", 10, 2, , , , "Gini-Simpson Diversity Index attractions"},
        {"GSIndex", "Real", 10, 2, , , , "Gini-Simpson Diversity Index|(Measures mixed use)"}
    }
    RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})
    SetView(se_vw)
    internal_set = CreateSet("internal")
    SelectByQuery(internal_set, "several", "Select * where Type = 'Internal'")
    // Calculate g and total g for each zone
    g = null
    for i = 1 to v_fields.length do
        field = v_fields[i]
        rate = v_rates[i]

        v = nz(GetDataVector(se_vw + "|" + internal_set, field, ))
        g.(field) = v * rate
        if i = 1 then total_g = Vector(v.length, "real", {Constant: 0})
        total_g = total_g + g.(field)
    end
    SetDataVector(se_vw + "|" + internal_set, "GSAttractions", total_g, )
    total_g = if total_g = 0 then -1 else total_g
    // Calculate the sum of the ratios squared: Sum((g/total_g)^2)
    sum_ratio_squared = Vector(total_g.length, "real", {Constant: 0})
    for i = 1 to v_fields.length do
        field = v_fields[i]
        rate = v_rates[i]

        sum_ratio_squared = sum_ratio_squared + pow(g.(field) / total_g, 2)
    end
    sum_ratio_squared = if sum_ratio_squared = 0 then .5 else sum_ratio_squared
    // Calculate final index value for each zone
    v_index = 1 - sum_ratio_squared
    SetDataVector(se_vw + "|" + internal_set, "GSIndex", v_index, )

    CloseView(se_vw)
endmacro

/*
Calculates intersection approach density.
Also does some quick density calculations.
*/

Macro "Calc Intersection Approach Density" (Args)

    link_dbd = Args.Links
    taz_dbd = Args.TAZs
    se_file = Args.SE
    
    // Create maps/views and add fields

    {map, {node_lyr, link_lyr}} = RunMacro("Create Map", {file: link_dbd})
    {taz_lyr} = GetDBLayers(taz_dbd)
    taz_lyr = AddLayer(map, taz_lyr, taz_dbd, taz_lyr)
    se_vw = OpenTable("se", "FFB", {se_file})
    node_fields =  {{"Approaches", "Integer", 10, ,,,, "Number of collector/arterial links connected to this node"}}
    RunMacro("Add Fields", {view: node_lyr, a_fields: node_fields})
    link_fields =  {{"to_count", "Integer", 10, ,,,, }}
    RunMacro("Add Fields", {view: link_lyr, a_fields: link_fields})
    taz_fields =  {{"ApproachDensity", "Real", 10, 2,,,, "Number of intersection approaches per sq mi"}}
    RunMacro("Add Fields", {view: taz_lyr, a_fields: taz_fields})
    se_fields = {
        taz_fields[1],
        {"GSAttrDens", "Real", 10, 2,,,, "Density of GS attractions"},
        {"IndEmpDensity", "Real", 10, 2,,,, "Density of industrial employment"}
    }
    RunMacro("Add Fields", {view: se_vw, a_fields: se_fields})
    
    
    // Determine intersection approach densities. Only consider approaches
    // from arterials/collectors.
    v_type = GetDataVector(link_lyr + "|", "HCMType", )
    v_count = if v_type = "Arterial" or v_type = "Collector" then 1 else 0
    SetDataVector(link_lyr + "|", "to_count", v_count, )
    from_node = CreateNodeField(link_lyr, "from_node", node_lyr + ".ID", "From", )
    to_node = CreateNodeField(link_lyr, "to_node", node_lyr + ".ID", "To", )
    {, node_specs} = RunMacro("Get Fields", {view_name: node_lyr})
    {, link_specs} = RunMacro("Get Fields", {view_name: link_lyr})
    {, taz_specs} = RunMacro("Get Fields", {view_name: taz_lyr})
    {, se_specs} = RunMacro("Get Fields", {view_name: se_vw})
    aggr = aggr = {{"to_count", {{"Sum"}}}}
    jv = JoinViews("jv_from", node_specs.ID, link_specs.from_node, 
        {{"A", }, {"Fields", aggr}})
    v_approach = GetDataVector(jv + "|", "to_count", )
    CloseView(jv)
    jv = JoinViews("jv_to", node_specs.ID, link_specs.to_node, 
        {{"A", }, {"Fields", aggr}})
    v_approach2 = GetDataVector(jv + "|", "to_count", )
    v_approach = v_approach + v_approach2
    // Nodes with 2 approaches are just mid-block nodes
    v_approach = if nz(v_approach) < 3 then 0 else v_approach
    CloseView(jv)
    SetDataVector(node_lyr + "|", "Approaches", v_approach, )
    RunMacro("Remove Field", link_lyr, "to_count")
    ColumnAggregate(taz_lyr + "|", 0, node_lyr + "|", {
        {"ApproachDensity", "SUM", "Approaches", }
    }, )
    v_approach = GetDataVector(taz_lyr + "|", taz_specs.ApproachDensity, )
    v_area = GetDataVector(taz_lyr + "|", "Area", )
    v_approach = v_approach / v_area
    SetDataVector(taz_lyr + "|", "ApproachDensity", v_approach, )
    jv = JoinViews("jv", taz_specs.ID, se_specs.TAZ, )
    v_approach = GetDataVector(jv + "|", taz_specs.ApproachDensity, )
    SetDataVector(jv + "|", se_specs.ApproachDensity, v_approach, )

    // Calculate industry emp density
    v_ind = GetDataVector(jv + "|", se_specs.Industry, )
    v_ind_dens = v_ind / v_area
    SetDataVector(jv + "|", se_specs.IndEmpDensity, v_ind_dens, )

    // Attraction density
    v_attr = GetDataVector(jv + "|", se_specs.GSAttractions, )
    v_attr_dens = v_attr / v_area
    SetDataVector(jv + "|", se_specs.GSAttrDens, v_attr_dens, )

    CloseView(se_vw)
    CloseView(jv)
    CloseMap()
endmacro

/*

*/

Macro "Calc Percent of Zone Near Bus Stop" (Args)

    route_file = Args.Routes
    taz_file = Args.TAZs
    se_file = Args.SE

    // Create map/views
    {map, {route_lyr, stop_lyr, , node_lyr, link_lyr}} = RunMacro("Create Map", {file: route_file})
    {taz_lyr} = GetDBLayers(taz_file)
    taz_lyr = AddLayer(map, taz_lyr, taz_file, taz_lyr, )
    taz_fields =  {{"PctNearBusStop", "Real", 10, 2,,,, "Percent of zone within 1/4 mile of bus stop|(e.g. .5 = 50%"}}
    RunMacro("Add Fields", {view: taz_lyr, a_fields: taz_fields})
    se_vw = OpenTable("se", "FFB", {se_file})
    RunMacro("Add Fields", {view: se_vw, a_fields: taz_fields})

    // Buffer and intersect
    SetLayer(stop_lyr)
    buffer_dbd = GetTempFileName(".dbd")
    buff_lyr = "buffer"
    CreateBuffers(buffer_dbd, buff_lyr, {}, "Value", {.25}, {Interior: "Merged", Exterior: "Merged"})
    buff_lyr = AddLayer(map, buff_lyr, buffer_dbd, buff_lyr, )
    intersection_file = GetTempFileName(".bin")
    ComputeIntersectionPercentages({taz_lyr, buff_lyr}, intersection_file, )
    int_vw = OpenTable("int", "FFB", {intersection_file})

    // Munge intersection table into a form that can be joined to the se table
    a_fields =  {{"count", "Integer", 10, ,,,, }}
    RunMacro("Add Fields", {view: int_vw, a_fields: a_fields})
    agg_vw = SelfAggregate("agg", int_vw + ".Area_1", )
    jv = JoinViews("jv", int_vw + ".Area_1", agg_vw + ".[GroupedBy(Area_1)]", )
    v_count = GetDataVector(jv + "|", agg_vw + ".[Count(int)]", )
    SetDataVector(jv + "|", int_vw + ".count", v_count, )
    CloseView(jv)
    CloseView(agg_vw)
    SetView(int_vw)
    v_pct = GetDataVector(int_vw + "|", "Percent_1", )
    v_a2 = GetDataVector(int_vw + "|", "Area_2", )
    v_pct = if v_a2 = 0 then 1 - v_pct else v_pct
    SetDataVector(int_vw + "|", "Percent_1", v_pct, )
    query = "Select * where Area_2 = 0 and count = 2"
    n = SelectByQuery("to_delete", "several", query)
    if n > 0 then DeleteRecordsInSet("to_delete")

    // Add to se data table
    jv = JoinViews("jv", se_vw + ".TAZ", int_vw + ".Area_1", )
    v_pct = GetDataVector(jv + "|", "Percent_1", )
    SetDataVector(jv + "|", "PctNearBusStop", v_pct, )
    CloseView(jv)

    CloseView(int_vw)
    CloseView(se_vw)
    CloseMap(map)
endmacro