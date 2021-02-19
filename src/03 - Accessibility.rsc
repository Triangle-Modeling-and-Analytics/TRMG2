/*

*/

Macro "Accessibility" (Args)

    RunMacro("Calc Gini-Simpson Diversity Index", Args)
    RunMacro("Calc Intersection Approach Density", Args)

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
    RunMacro("Add Fields", {view: taz_lyr, a_fields: taz_fields})
    
    
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
    v = GetDataVector(taz_lyr + "|", taz_specs.ApproachDensity, )
    v_area = GetDataVector(taz_lyr + "|", "Area", )
    v = v / v_area
    SetDataVector(taz_lyr + "|", "ApproachDensity", v, )
    jv = JoinViews("jv", taz_specs.ID, se_specs.TAZ, )
    v = GetDataVector(jv + "|", taz_specs.ApproachDensity, )
    SetDataVector(jv + "|", se_specs.ApproachDensity, v, )

    CloseView(se_vw)
    CloseMap()
endmacro