/*
Calls various macros that calculate different accessibility measures.
*/

Macro "Accessibility" (Args)

    RunMacro("Calc GS and Walkability Attractions", Args)
    RunMacro("Calc Gini-Simpson Diversity Index", Args)
    RunMacro("Calc Intersection Approach Density", Args)
    RunMacro("Calc Walkability Score", Args)
    RunMacro("Calculate NM Interaction Terms", Args)
    RunMacro("Create Accessibility Skims", Args)
    RunMacro("Calculate Logsum Accessibilities", Args)
    RunMacro("Calc Percent of Zone Near Bus Stop", Args)
    RunMacro("Calculate TNC Wait Time", Args)

    return(1)
endmacro

/*
Calculate attractions that will be used for the Walkability model
and the Gini-Simpson Diversity Index calculation.
*/

Macro "Calc GS and Walkability Attractions" (Args)

    se_file = Args.SE
    rate_file = Args.[Access Attr Rates]

    se_vw = OpenTable("se", "FFB", {se_file})
    {drive, folder, name, ext} = SplitPath(rate_file)
    RunMacro("Create Sum Product Fields", {
        view: se_vw, factor_file: rate_file,
        field_desc: "GS and Walkability Attractions|See " + name + ext + " for details."
    })

    CloseView(se_vw)
endmacro

/*
The Gini-Simpson Diversity Index is a measure of mixed use. If a zone only has
one type of 'thing' (households or specific emp type), it will have a score
of 0. As the number of different uses increases, the score rises to a max
of 1. In TRMG2, there are three 'things', which are the three attraction types:
  * gs_home_attr
  * gs_work_attr
  * gs_other_attr
*/

Macro "Calc Gini-Simpson Diversity Index" (Args)

    se_file = Args.SE

    se_vw = OpenTable("se", "FFB", {se_file})
    a_fields = {
        {"gs_total_attr", "Real", 10, 2, , , , "Gini-Simpson Diversity Index attractions"},
        {"GSIndex", "Real", 10, 2, , , , "Gini-Simpson Diversity Index|(Measures mixed use)"}
    }
    RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})
    SetView(se_vw)
    internal_set = CreateSet("internal")
    SelectByQuery(internal_set, "several", "Select * where Type = 'Internal'")
    // Calculate g and total g for each zone
    
    
    {gs_home_attr, gs_work_attr, gs_other_attr} = GetDataVectors(
        se_vw + "|" + internal_set,
        {"gs_home_attr", "gs_work_attr", "gs_other_attr"},
    )
    total = gs_home_attr + gs_work_attr + gs_other_attr
    // // Calculate the sum of the ratios squared: Sum((g/total_g)^2)
    sum_ratio_squared = pow(gs_home_attr / total, 2)
    sum_ratio_squared = sum_ratio_squared + pow(gs_work_attr / total, 2)
    sum_ratio_squared = sum_ratio_squared + pow(gs_other_attr / total, 2)
    sum_ratio_squared = if sum_ratio_squared = 0 then .5 else sum_ratio_squared
    v_index = 1 - sum_ratio_squared
    SetDataVector(se_vw + "|" + internal_set, "GSIndex", v_index, )
    SetDataVector(se_vw + "|" + internal_set, "gs_total_attr", total, )

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
        {"walk_attr_dens", "Real", 10, 2,,,, "Density of GS attractions"},
        {"IndEmpDensity", "Real", 10, 2,,,, "Density of industrial employment"}
    }
    RunMacro("Add Fields", {view: se_vw, a_fields: se_fields})
    
    
    // Determine intersection approach densities. Only consider approaches
    // from arterials/collectors/locals.
    v_type = GetDataVector(link_lyr + "|", "HCMType", )
    v_count = if v_type = "MajorArterial" or v_type = "Arterial" or v_type = "MajorCollector" or v_type = "Collector" or v_type = "Local" then 1 else 0
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
    v_attr = GetDataVector(jv + "|", se_specs.gs_total_attr, )
    v_attr_dens = v_attr / v_area
    SetDataVector(jv + "|", se_specs.walk_attr_dens, v_attr_dens, )

    CloseView(se_vw)
    CloseView(jv)
    CloseMap(map)
endmacro

/*
Creates the "Walkability" field on the SE data (and some others), that gives
the probability of a trip being a walk trip.
*/

Macro "Calc Walkability Score" (Args)

    se_file = Args.SE
    model_file = Args.[Input Folder] + "\\accessibility\\walkability.mdl"

    // Normalize utility variables
    se_vw = OpenTable("se", "FFB", {se_file})
    a_fields =  {
        {"ApproachDensity_z", "Real", 10, 2,,,, "normalized for walkability choice model"},
        {"IndEmpDensity_z", "Real", 10, 2,,,, "normalized for walkability choice model"},
        {"walk_attr_dens_z", "Real", 10, 2,,,, "normalized for walkability choice model"},
        {"GSIndex_z", "Real", 10, 2,,,, "normalized for walkability choice model"},
        {"Walkability", "Real", 10, 2,,,, "Probability of walk trips. Result of simple choice model."}
    }
    RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})
    data = GetDataVectors(
        se_vw + "|",
        {"ApproachDensity", "IndEmpDensity", "walk_attr_dens", "GSIndex"},
        {OptArray: true}
    )
    for i = 1 to data.length do
        name = data[i][1]
        v = data[i][2]

        mu = v.mean()
        sd = v.sdev()
        z = (v - mu) / sd
        new_name = name + "_z"
        set.(new_name) = z
    end
    SetDataVectors(se_vw + "|", set, )

    // Apply mc model
    o = CreateObject("Choice.Mode")
    o.ModelFile = model_file
    o.AddTableSource({Label: "sedata", Filter: "Type = 'Internal'", FileName: se_file})
    o.DropModeIfMissing = true
    o.SkipValuesBelow = 0.001
    out_file = GetTempFileName("*.bin")
    o.OutputProbabilityFile = out_file
    o.AggregateModel = false
    ok = o.Run()
    
    // Transfer results to SE data
    out_vw = OpenTable("output", "FFB", {out_file})
    {, out_specs} = RunMacro("Get Fields", {view_name: out_vw})
    {, se_specs} = RunMacro("Get Fields", {view_name: se_vw})
    jv = JoinViews("jv", se_specs.TAZ, out_specs.ID, )
    v = GetDataVector(jv + "|", "walk Probability", )
    SetDataVector(jv + "|", "Walkability", v, )
    CloseView(jv)
    CloseView(out_vw)
    CloseView(se_vw)
endmacro

/*
The walk accessibility metric has special attraction fields that
are calculated by interacting the basic SE data fields with the
walkability score. This can be intepreted as the 'walkable' attractions
in the zone. In other words, highly walkable zones with lots of stuff
in them will look most attractive.
*/

Macro "Calculate NM Interaction Terms" (Args)

    se_file = Args.SE

    se_vw = OpenTable("se", "FFB", {se_file})

    // Calculate the interaction fields needed for NM attractions
    a_fields = {
        "HH",
        "K12",
        "StudGQ_NCSU",
        "StudGQ_UNC",
        "StudGQ_DUKE",
        "StudGQ_NCCU",
        "CollegeOn",
        "Retail",
        "TotalEmp"
    }
    v_walkability = GetDataVector(se_vw + "|", "Walkability", )
    for field in a_fields do
        new_name = "w" + field
        a_fields_to_add = a_fields_to_add + {
            {new_name, "Real", 10, 2, , , , field + " * Walkability|~'Walkable attractors'|Used in walk accessibility calculation"}
        }
        v = GetDataVector(se_vw + "|", field, )
        data.(new_name) = v * v_walkability
    end
    RunMacro("Add Fields", {view: se_vw, a_fields: a_fields_to_add})
    SetDataVectors(se_vw + "|", data, )

    CloseView(se_vw)
endmacro

/*
These skims are created outside the feedback loop to calculate accessibility
measures based on logsums.
*/

Macro "Create Accessibility Skims" (Args)

    link_dbd = Args.Links
    output_dir = Args.[Output Folder]

    // SOV Skim
    obj = CreateObject("Network.Skims")
    obj.Network = output_dir + "/networks/net_AM_sov.net"
    obj.LayerDB = link_dbd
    obj.Origins = "Centroid = 1" 
    obj.Destinations = "Centroid = 1"
    obj.Minimize = "FFTime"
    obj.AddSkimField({"Length", "All"})
    out_files.sov = output_dir + "/skims/roadway/accessibility_sov_AM.mtx"
    obj.OutputMatrix({MatrixFile: out_files.sov, Matrix: "SOV Skim"})
    ret_value = obj.Run()
    // Walk Skim
    obj.Network = output_dir + "/networks/net_walk.net"
    obj.Minimize = "WalkTime"
    out_files.walk = output_dir + "/skims/nonmotorized/walk_skim.mtx"
    obj.OutputMatrix({MatrixFile: out_files.walk, Matrix: "Walk Skim"})
    ret_value = obj.Run()
    // Bike Skim
    obj.Network = output_dir + "/networks/net_bike.net"
    obj.Minimize = "BikeTime"
    out_files.bike = output_dir + "/skims/nonmotorized/bike_skim.mtx"
    obj.OutputMatrix({MatrixFile: out_files.bike, Matrix: "Bike Skim"})
    ret_value = obj.Run()
    // Transit Skim
    overrides = {
        periods: {"AM"},
        access_modes: {"w"},
        transit_modes: {"all"}
    }
    RunMacro("Transit Skims", Args, overrides)

    // intrazonals
    obj = CreateObject("Distribution.Intrazonal")
    obj.OperationType = "Replace"
    obj.TreatMissingAsZero = false
    obj.Neighbours = 3
    obj.Factor = .75
    obj.SetMatrix({MatrixFile: out_files.sov, Matrix: "FFTime"})
    ok = obj.Run()
    obj.SetMatrix({MatrixFile: out_files.sov, Matrix: "Length (Skim)"})
    ok = obj.Run()
    obj.SetMatrix({MatrixFile: out_files.walk, Matrix: "WalkTime"})
    ok = obj.Run()
    obj.SetMatrix({MatrixFile: out_files.walk, Matrix: "Length (Skim)"})
    ok = obj.Run()
    obj.SetMatrix({MatrixFile: out_files.bike, Matrix: "BikeTime"})
    ok = obj.Run()
    obj.SetMatrix({MatrixFile: out_files.bike, Matrix: "Length (Skim)"})
    ok = obj.Run()
endmacro

/*
This macro calculates an array of logsum-based accessibility measures and
stores them on the SE table.
*/

Macro "Calculate Logsum Accessibilities" (Args)

    se_file = Args.SE
    param_file = Args.[Input Folder] + "\\accessibility\\accessibilities.csv"
    skim_dir = Args.[Output Folder] + "\\skims"
    sov_skim = skim_dir + "\\roadway\\accessibility_sov_AM.mtx"
    walk_skim = skim_dir + "\\nonmotorized\\walk_skim.mtx"
    transit_skim = skim_dir + "\\transit\\skim_AM_w_all.mtx"

    RunMacro("Accessibility Calculator", {
        table: se_file,
        params: param_file,
        skims: {sov: sov_skim, walk: walk_skim, transit: transit_skim}
    })
endmacro

/*
Determines what percent of each zone is within a certain distance of
bus stops.
*/

Macro "Calc Percent of Zone Near Bus Stop" (Args)

    route_file = Args.Routes
    taz_file = Args.TAZs
    se_file = Args.SE

    // Create map/views
    {map, {route_lyr, stop_lyr, , node_lyr, link_lyr}} = RunMacro("Create Map", {file: route_file})
    {taz_lyr} = GetDBLayers(taz_file)
    taz_lyr = AddLayer(map, taz_lyr, taz_file, taz_lyr, )
    a_fields =  {{"PctNearBusStop", "Real", 10, 2,,,, "Percent of zone within 1/4 mile of bus stop|(e.g. .5 = 50%"}}
    se_vw = OpenTable("se", "FFB", {se_file})
    RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})

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

/*
Calculates the average wait time for an Uber/Lyft for each zone
*/

Macro "Calculate TNC Wait Time" (Args)

    se_file = Args.SE

    se_vw = OpenTable("se", "FFB", {se_file})
    a_fields =  {
        {"PKTNCWait", "Real", 10, 2,,,, "TNC wait time in the peak"},
        {"OPTNCWait", "Real", 10, 2,,,, "TNC wait time in the off peak"}
    }
    RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})
    v_access = GetDataVector(se_vw + "|", "access_general_sov", )
    v_op_wait = 43.10 - 1534.4 / v_access + 13030.36 / pow(v_access, 2) + 2
    v_pk_wait = v_op_wait + 3.5
    SetDataVector(se_vw + "|", "PKTNCWait", v_pk_wait, )
    SetDataVector(se_vw + "|", "OPTNCWait", v_op_wait, )
    CloseView(se_vw)
endmacro