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
* cluster_data
    * String
    * File path of the CSV file containing theta/nesting coefficients, ASCs,
      and IZ coefficients for cluster choice
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
        // Check input options
        if ClassOpts.output_dir = null then Throw("NestedDC: 'output_dir' is null")
        if ClassOpts.trip_type = null then Throw("NestedDC: 'trip_type' is null")
        if ClassOpts.period = null then Throw("NestedDC: 'period' is null")
        if ClassOpts.segments = null then ClassOpts.segments = {null}
        if ClassOpts.zone_utils = null then Throw("NestedDC: 'zone_utils' is null")
        if ClassOpts.cluster_data = null then Throw("NestedDC: 'cluster_data' is null")
        if ClassOpts.primary_spec = null then Throw("NestedDC: 'primary_spec' is null")
        if ClassOpts.dc_spec = null then Throw("NestedDC: 'dc_spec' is null")
        if ClassOpts.cluster_equiv_spec = null then Throw("NestedDC: 'cluster_equiv_spec' is null")
        if ClassOpts.tables = null then Throw("NestedDC: 'tables' is null")
        if ClassOpts.matrices = null then Throw("NestedDC: 'matrices' is null")

        // Create additional class options
        self.ClassOpts = ClassOpts
        self.ClassOpts.mdl_dir = ClassOpts.output_dir + "/model_files"
        self.ClassOpts.prob_dir = ClassOpts.output_dir + "/probabilities"
        self.ClassOpts.logsum_dir = ClassOpts.output_dir + "/logsums"
        self.ClassOpts.util_dir = ClassOpts.output_dir + "/utilities"
        {drive, path, name, ext} = SplitPath(self.ClassOpts.cluster_data)
        file_name = self.ClassOpts.output_dir + "/" + name + "_utils.csv"
        self.ClassOpts.cluster_utils = file_name
    enditem

    Macro "Run" do
        // Run zone-level DC
        self.util_file = self.ClassOpts.zone_utils
        self.zone_level = "true"
        self.RunChoiceModels(zone_opts)
        
        // Build cluster-level choice data
        self.BuildClusterData()

        // Run cluster-level model
        self.util_file = self.ClassOpts.cluster_utils
        self.zone_level = "false"
        self.dc_spec = {DestinationsSource: "mtx", DestinationsIndex: "Col_AggregationID"}
        self.RunChoiceModels(cluster_opts)

        // Combine cluster- and zone-level probabilities into final results
        self.CalcFinalProbs()
    enditem

    /*
    Generic choice model calculator.

    Inputs (other than Class inputs)
    * util_file
        * String
        * Either `zone_utils` or `cluster_utils` from the ClassOpts
    * zone_level
        * True/False
        * If this is being run on the zone level (false = cluster level)
    */

    Macro "RunChoiceModels" do
        
        util_file = self.util_file
        zone_level = self.zone_level
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
        
        // if nest_file <> null then nest_tree = self.ImportChoiceSpec(nest_file)

        for seg in segments do
            tag = trip_type
            if seg <> null then tag = tag + "_" + seg
            if period <> null then tag = tag + "_" + period

            // Set up and run model
            obj = CreateObject("PMEChoiceModel", {ModelName: tag})
            obj.Segment = seg

            if zone_level then do
                obj.OutputModelFile = mdl_dir + "\\" + tag + "_zone.dcm"
            end else do
                obj.OutputModelFile = mdl_dir + "\\" + tag + "_cluster.dcm"
                matrices = matrices + {
                    mtx: {File: logsum_dir + "/agg_zonal_ls_" + tag + ".mtx"}
                }
            end
            
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

            // Add alternatives, utility and specify the primary source
            // if nest_tree <> null then
            //     obj.AddAlternatives({AlternativesTree: nest_tree})
            if zone_level 
                then obj.AddPrimarySpec(primary_spec)
                else obj.AddPrimarySpec({Name: "mtx"})
            obj.AddDestinations(dc_spec)
            obj.AddUtility({UtilityFunction: util})
            
            // Specify outputs
            if zone_level then do
                output_opts = {
                    Probability: prob_dir + "\\probability_" + tag + "_zone.mtx",
                    Utility: util_dir + "\\utility_" + tag + "_zone.mtx"
                }
            end else do
                output_opts = {
                    Probability: prob_dir + "\\probability_" + tag + "_cluster.mtx",
                    Utility: util_dir + "\\utility_" + tag + "_cluster.mtx",
                    Logsum: logsum_dir + "\\logsum_" + tag + "_cluster.mtx"
                }
            end
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
    Aggregates the DC logsums into cluster-level values. Also writes a simple
    dc util spec csv file.
    */

    Macro "BuildClusterData" do

        trip_type = self.ClassOpts.trip_type
        period = self.ClassOpts.period
        segments = self.ClassOpts.segments
        equiv_spec = self.ClassOpts.cluster_equiv_spec
        output_dir = self.ClassOpts.output_dir
        util_dir = self.ClassOpts.util_dir
        logsum_dir = self.ClassOpts.logsum_dir
        cluster_data = self.ClassOpts.cluster_data
        cluster_utils = self.ClassOpts.cluster_utils

        // Collect vectors of cluster names, IDs, and theta values
        theta_vw = OpenTable("thetas", "CSV", {cluster_data})
        vecOpts.[Sort Order] = {{"Cluster", "Ascending"}}
        {
            v_cluster_ids, v_cluster_names, v_cluster_theta, v_cluster_asc,
            v_cluster_ic, v_additional_asc, v_additional_ic
        } = GetDataVectors(
            theta_vw + "|",
            {"Cluster", "ClusterName", "Theta", "ASC", "IC", "Calibrated_DeltaASC", "Calibrated_DeltaIC"},
            vecOpts
        )
        CloseView(theta_vw)

        for segment in segments do
            name = trip_type + "_" + segment + "_" + period
            mtx_file = util_dir + "/utility_" + name + "_zone.mtx"
            mtx = CreateObject("Matrix", mtx_file)
            mtx.AddCores({"ScaledTotal", "ExpScaledTotal", "IntraCluster"})
            cores = mtx.GetCores()

            // The utilities must be scaled by the cluster thetas, which requires
            // an index for each cluster
            cores.ScaledTotal := cores.Total
            self.CreateClusterIndices(mtx)
            for i = 1 to v_cluster_ids.length do
                cluster_id = v_cluster_ids[i]
                cluster_name = v_cluster_names[i]
                theta = v_cluster_theta[i]

                mtx.SetColIndex(cluster_name)
                cores = mtx.GetCores()
                cores.ScaledTotal := cores.ScaledTotal / theta

                // Also mark intra-cluster ij pairs
                mtx.SetRowIndex(cluster_name)
                cores = mtx.GetCores()
                cores.IntraCluster := 1
                mtx.SetRowIndex("Origins")
            end

            // e^(scaled_x)
            mtx.SetColIndex("Destinations")
            cores = mtx.GetCores()
            cores.ExpScaledTotal := exp(cores.scaledTotal)

            // Aggregate the columns into clusters
            agg = mtx.Aggregate({
                Matrix: {FileName: logsum_dir + "/agg_zonal_ls_" + name + ".mtx", MatrixLabel: "Cluster Logsums"},
                Matrices: {"ExpScaledTotal", "IntraCluster"}, 
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
            agg.AddCores({"LnSumExpScaledTotal", "final", "ic", "asc"})
            cores = agg.GetCores()
            cores.LnSumExpScaledTotal := Log(cores.[Sum of ExpScaledTotal])
            cores.final := cores.LnSumExpScaledTotal * v_cluster_theta
            cores.ic := if nz(cores.[Sum of IntraCluster]) > 0 then 1 else 0
            cores.ic := cores.ic * (v_cluster_ic + v_additional_ic)
            cores.asc := v_cluster_asc + v_additional_asc
        end

        // Write the simple cluster_utils csv file needed to run cluster dc
        util_vw = CreateTable("util", , "MEM", {
            {"Expression", "String", 32, },
            {"Segment", "String", 32, },
            {"Coefficient", "Real", 32, 2},
            {"Description", "String", 32, }
        })
        AddRecords(util_vw, {"Expression", "Coefficient"}, {
            {"mtx.asc", 1},
            {"mtx.ic", 1},
            {"mtx.final", 1}
        }, )
        ExportView(util_vw + "|", "CSV", cluster_utils, , {"CSV Header": "true"})
        CloseView(util_vw)
    enditem

    /*
    Creates indices that can be used to select the zones in each cluster
    */

    Macro "CreateClusterIndices" (mtx) do
        
        cluster_data = self.ClassOpts.cluster_data
        equiv_spec = self.ClassOpts.cluster_equiv_spec

        theta_vw = OpenTable("thetas", "CSV", {cluster_data})
        {v_cluster_ids, v_cluster_names} = GetDataVectors(
            theta_vw + "|",
            {"Cluster", "ClusterName"},
        )
        CloseView(theta_vw)

        for i = 1 to v_cluster_ids.length do
            cluster_id = v_cluster_ids[i]
            cluster_name = v_cluster_names[i]

            mtx.AddIndex({
                Matrix: mtx.GetMatrixHandle(),
                IndexName: cluster_name,
                Filter: "Cluster = " + String(cluster_id),
                Dimension: "Both",
                TableName: equiv_spec.File,
                OriginalID: equiv_spec.ZoneIDField,
                NewID: equiv_spec.ZoneIDField
            })
        end
    enditem

    /*
    After the zonal and cluster probabilities are calculated, they must be
    combined into a final probability of choosing each zone. This is the
    prob of choosing a cluster * the prob of choosing a zone within that
    cluster. The zonal probabilities must be scaled so that they add up to
    1 within each cluster.
    */

    Macro "CalcFinalProbs" do

        trip_type = self.ClassOpts.trip_type
        period = self.ClassOpts.period
        segments = self.ClassOpts.segments
        prob_dir = self.ClassOpts.prob_dir
        cluster_data = self.ClassOpts.cluster_data

        for segment in segments do
            name = trip_type + "_" + segment + "_" + period
            cluster_file = prob_dir + "/probability_" + name + "_cluster.mtx"
            zone_file = prob_dir + "/probability_" + name + "_zone.mtx"

            z_mtx = CreateObject("Matrix", zone_file)
            c_mtx = CreateObject("Matrix", cluster_file)

            // Add cluster indices to the zonal matrix
            self.CreateClusterIndices(z_mtx)
            
            theta_vw = OpenTable("thetas", "CSV", {cluster_data})
            {v_cluster_ids, v_cluster_names} = GetDataVectors(
                theta_vw + "|",
                {"Cluster", "ClusterName"},
            )
            CloseView(theta_vw)

            z_mtx.AddCores({"scaled_prob", "final_prob"})
            for i = 1 to v_cluster_ids.length do
                cluster_id = v_cluster_ids[i]
                cluster_name = v_cluster_names[i]

                v_cluster_prob = c_mtx.GetVector({"Core": "Total", "Column": cluster_id})
                z_mtx.SetColIndex(cluster_name)
                v_row_sum = z_mtx.GetVector({"Core": "Total", Marginal: "Row Sum"})
                cores = z_mtx.GetCores()
                cores.scaled_prob := cores.Total / v_row_sum
                cores.final_prob := cores.scaled_prob * v_cluster_prob
            end
        end
    enditem
endclass