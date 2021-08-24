/*
A class that implements a nested DC model

Inputs
* output_dir
    * String
    * Output directory where subfolders and files will be written.
* trip_type
    * String
    * Name of the trip type/purpose
* zone_utils
    * String
    * File path of the CSV file containing utility terms for zonal choice
* cluster_utils
    * String
    * File path of the CSV file containing utility terms for cluster choice
* cluster_thetas
    * String
    * File path of the CSV file containing theta/nesting coefficients for cluster choice
* period
    * Optional string (default: null)
    * Time of day. Only used for file naming, so you can use "daily", "all",
    * "am", or just leave it blank.
* segments
    * Optional array of strings (default: null)
    * Names of market segments. If provided, MC will be applied in a loop
    over the segments.
* primary_spec
    * An array that configures the primary data source. It includes
    * Name: the name of the data source (matching `source_name` in `tables` or `matices`)
    * If the primary source is a table, then it also includes:
        * OField: name of the origin field
        * DField: name of the destination field (if applicable)
* dc_spec
    * Array
    * Specifies where to find the list of destination zones.
    * Example: {DestinationsSource: "sov_skim", DestinationsIndex: "Destination"}
* cluster_equiv_spec
    * Array
    * Specifies the file and fields used to build clusters from zones
    * Example: {File: "se.bin", ZoneIDField: "TAZ", ClusterIDField: "Cluster"}
* tables
    * Optional array of table sources (default: null)
    * `tables` and `matrices` cannot both be null
    * Each item in `tables` must include:
    * source_name: (string) name of the source
    * File: (string) file path of the table
    * IDField: (string) name of the ID field in the table
* matrices
    * Optional array of matrix sources(default: null)
    * `tables` and `matrices` cannot both be null
    * Each item in `matrices` must include:
    * source_name: (string) name of the source
    * File: (string) file path of the matrix
*/

Class "NestedDC" (ClassOpts)

    init do
        if ClassOpts.output_dir = null then Throw("NestedDC: 'output_dir' is null")
        if ClassOpts.trip_type = null then Throw("NestedDC: 'trip_type' is null")
        if ClassOpts.period = null then Throw("NestedDC: 'period' is null")
        if ClassOpts.segments = null then ClassOpts.segments = {null}
        if ClassOpts.zone_utils = null then Throw("NestedDC: 'zone_utils' is null")
        if ClassOpts.cluster_utils = null then Throw("NestedDC: 'cluster_utils' is null")
        if ClassOpts.cluster_thetas = null then Throw("NestedDC: 'cluster_thetas' is null")
        if ClassOpts.primary_spec = null then Throw("NestedDC: 'primary_spec' is null")
        if ClassOpts.dc_spec = null then Throw("NestedDC: 'dc_spec' is null")
        if ClassOpts.cluster_equiv_spec = null then Throw("NestedDC: 'cluster_equiv_spec' is null")
        if ClassOpts.tables = null then Throw("NestedDC: 'tables' is null")
        if ClassOpts.matrices = null then Throw("NestedDC: 'matrices' is null")

        self.ClassOpts = ClassOpts
        self.ClassOpts.mdl_dir = ClassOpts.output_dir + "/model_files"
        self.ClassOpts.prob_dir = ClassOpts.output_dir + "/probabilities"
        self.ClassOpts.logsum_dir = ClassOpts.output_dir + "/logsums"
        self.ClassOpts.util_dir = ClassOpts.output_dir + "/utilities"
    enditem

    Macro "Run" do
        // Run zone-level DC
        zone_opts.util_file = self.ClassOpts.zone_utils
        zone_opts.dc = "true"
        self.RunChoiceModels(zone_opts)
        
        // Build cluster-level choice data
        self.BuildClusterData()
Throw()

        // Run cluster-level model
        util_file = self.ClassOpts.cluster_utils
        self.RunChoiceModels(util_file)
    enditem

    /*
    Generic choice model calculator.

    Inputs
    * util_file
        * String
        * Either `zone_utils` or `cluster_utils` from the ClassOpts
    * dc
        * True/False
        * If the model will be DC (if false then MC)
    */

    Macro "RunChoiceModels" (MacroOpts) do
        util_file = MacroOpts.util_file
        dc = MacroOpts.dc

        dc_spec = self.ClassOpts.dc_spec
        trip_type = self.ClassOpts.trip_type
        segments = self.ClassOpts.segments
        period = self.ClassOpts.period
        tables = self.ClassOpts.tables
        matrices = self.ClassOpts.matrices
        primary_spec = self.ClassOpts.primary_spec

        // Create output subdirectories
        mdl_dir = self.ClassOpts.mdl_dir
        if GetDirectoryInfo(mdl_dir, "All") = null then CreateDirectory(mdl_dir)
        prob_dir = self.ClassOpts.prob_dir
        if GetDirectoryInfo(prob_dir, "All") = null then CreateDirectory(prob_dir)
        logsum_dir = self.ClassOpts.logsum_dir
        if GetDirectoryInfo(logsum_dir, "All") = null then CreateDirectory(logsum_dir)
        util_dir = self.ClassOpts.util_dir
        if GetDirectoryInfo(util_dir, "All") = null then CreateDirectory(util_dir)

        // Import util CSV file into an options array
        util = self.ImportChoiceSpec(util_file)
        
        if nest_file <> null then nest_tree = self.ImportChoiceSpec(nest_file)

        for seg in segments do
            tag = trip_type
            if seg <> null then tag = tag + "_" + seg
            if period <> null then tag = tag + "_" + period

            // Set up and run model
            obj = CreateObject("PMEChoiceModel", {ModelName: tag})
            obj.Segment = seg
            
            if dc = "false"
                then obj.OutputModelFile = mdl_dir + "\\" + tag + ".mdl"
                else obj.OutputModelFile = mdl_dir + "\\" + tag + ".dcm"
            
            // Add sources
            for i = 1 to tables.length do
                source_name = tables[i][1]
                source = tables.(source_name)

                obj.AddTableSource({
                    SourceName: source_name,
                    File: source.file,
                    IDField: source.IDField,
                    JoinSpec: source.JoinSpec
                })
            end
            for i = 1 to matrices.length do
                source_name = matrices[i][1]
                source = matrices.(source_name)

                obj.AddMatrixSource({
                    SourceName: source_name,
                    File: source.file
                })
            end
            
            // Add destinations if a DC model
            if dc then obj.AddDestinations(dc_spec)

            // Add alternatives, utility and specify the primary source
            if nest_tree <> null then
                obj.AddAlternatives({AlternativesTree: nest_tree})
            obj.AddUtility({UtilityFunction: util})
            obj.AddPrimarySpec(primary_spec)
            
            // Specify outputs
            output_opts = {Probability: prob_dir + "\\probability_" + tag + ".mtx",
                            Logsum: logsum_dir + "\\logsum_" + tag + ".mtx"}
            if dc then output_opts = output_opts + {Utility: util_dir + "\\utility_" + tag + ".mtx"}
            obj.AddOutputSpec(output_opts)
            
            //obj.CloseFiles = 0 // Uncomment to leave files open, so you can save a workspace
            ret = obj.Evaluate()
            if !ret then
                Throw("Running mode choice model failed for: " + tag)
            obj = null
        end
    enditem

    Macro "ImportChoiceSpec" (file) do
        vw = OpenTable("Spec", "CSV", {file,})
        {flds, specs} = GetFields(vw,)
        vecs = GetDataVectors(vw + "|", flds, {OptArray: 1})
        
        util = null
        for fld in flds do
            util.(fld) = v2a(vecs.(fld))
        end
        CloseView(vw)
        Return(util)
    enditem

    /*
    Aggregates the DC logsums into cluster-level values
    */

    Macro "BuildClusterData" do

        trip_type = self.ClassOpts.trip_type
        period = self.ClassOpts.period
        segments = self.ClassOpts.segments
        equiv_spec = self.ClassOpts.cluster_equiv_spec
        util_dir = self.ClassOpts.util_dir
        logsum_dir = self.ClassOpts.logsum_dir
        cluster_thetas = self.ClassOpts.cluster_thetas

        // Collect vectors of cluster names, IDs, and theta values
        theta_vw = OpenTable("thetas", "CSV", {cluster_thetas})
        {v_cluster_ids, v_cluster_names, v_cluster_theta} = GetDataVectors(
            theta_vw + "|",
            {"Cluster", "ClusterName", "Theta"},
        )

        for segment in segments do
            name = trip_type + "_" + segment + "_" + period
            mtx_file = util_dir + "/utility_" + name + ".mtx"
            mtx = CreateObject("Matrix", mtx_file)
            mtx.AddCores({"ScaledTotal", "ExpScaledTotal"})
            cores = mtx.data.cores

            // The utilities must be scaled by the cluster thetas, which requires
            // an index for each cluster
            cores.ScaledTotal := cores.Total
            for i = 1 to v_cluster_ids.length do
                cluster_id = v_cluster_ids[i]
                cluster_name = v_cluster_names[i]
                theta = v_cluster_theta[i]

                mtx.AddIndex({
                    Matrix: mtx.data.MatrixHandle,
                    TableName: equiv_spec.File,
                    Filter: "Cluster = " + String(cluster_id),
                    Dimension: "Column",
                    OriginalID: equiv_spec.ZoneIDField,
                    NewID: equiv_spec.ZoneIDField,
                    IndexName: cluster_name
                })
                mtx.SetColIndex(cluster_name)
                cores = mtx.data.cores
                cores.ScaledTotal := cores.ScaledTotal / theta
            end

            // e^(scaled_x)
            mtx.SetColIndex("Destinations")
            cores = mtx.data.cores
            cores.ExpScaledTotal := exp(mtx.data.cores.scaledTotal)

            // Aggregate the columns into clusters
            agg = mtx.Aggregate({
                Matrix: {MatrixFile: util_dir + "/temp.mtx", MatrixLabel: "Districts"},
                Matrices: {"ExpScaledTotal"}, 
                Method: "Sum",
                Rows: {
                    Data: equiv_spec.File, 
                    MatrixID: equiv_spec.ZoneIDField, 
                    AggregationID: equiv_spec.ZoneIDField // i.e. don't aggregate rows
                },
                Cols: {
                    Data: equiv_spec.File, 
                    MatrixID: equiv_spec.ZoneIDField, 
                    AggregationID: equiv_spec.ClusterIDField
                }
            })
            o = CreateObject("Matrix", agg)
            o.AddCores({"LnSumExpScaledTotal"})
            o.data.cores.LnSumExpScaledTotal := Log(o.data.cores.[Sum of ExpScaledTotal])
            mc = o.data.cores.LnSumExpScaledTotal
            col_ids = V2A(GetMatrixVector(mc, {Index: "Column"}))
            ls_file = logsum_dir + "/cluster_ls_" + name + ".bin"
            ExportMatrix(
                mc,
                col_ids,
                "Rows",
                "FFB",
                ls_file,
            )
            // Convert the column names from IDs to names
            ls_vw = OpenTable("ls", "FFB", {ls_file})
            for i = 1 to v_cluster_ids.length do
                id = v_cluster_ids[i]
                name = v_cluster_names[i]
                RunMacro("Rename Field", ls_vw, String(id), name)
            end
            RunMacro("Rename Field", ls_vw, "Row_AggregationID", "TAZ")
            CloseView(ls_vw)
        end

    enditem
endclass