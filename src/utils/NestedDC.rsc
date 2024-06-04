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
    * File path of the CSV file containing utility terms for zonal choice or a PME table from the flowchart
* cluster_data
    * String
    * File path of the CSV file containing theta/nesting coefficients, ASCs,
      and IZ coefficients for cluster choice or a PME table from the flowchart
* period
    * Optional string (default: null)
    * Time of day. Only used for file naming, so you can use "daily", "all",
    * "am", or just leave it blank.
* segment
    * A string value containing the market segment and maybe matching the value in the Segment utility column.
    * The output files will have the segment in the name
    * Default value is null
* primary_spec
    * An array that configures the primary data source. It includes
    * Name: the name of the data source (matching `source_name` in `tables` or `matrices`)
    * Filter: Optional. Used if primary is a table source (e.g. Person database)
    * If the primary source is a table, then it also includes:
        * OField: name of the origin field
        * DField: name of the destination field (if applicable)
* dc_spec
    * Array
    * Specifies where to find the list of destination zones.
    * Example: {DestinationsSource: "sov_skim", DestinationsIndex: "Destination"}
* calc_final_prob
    * 1/0: Applies only to aggregate case. Dfault 1. Setting 0 skips final prob calculation
* cluster_equiv_spec
    * Array
    * Specifies the file and fields used to build clusters from zones
    * Example: {File: "se.bin", ZoneIDField: "TAZ", ClusterIDField: "Cluster"}
* tables
    * Optional array of table sources (default: null)ClassOpts.zone_utils
    * `tables` and `matrices` cannot both be null
    * Each item in `tables` must include:
    * source_name: (string) name of the source
    * File: (string) file path of the table or View: View name of the already opened table
    * IDField: (string) name of the ID field in the table
* matrices
    * Array of matrix sources. There always has to some matrix source (so that destinations can be specified)
    * `tables` and `matrices` cannot both be null
    * Each item in `matrices` must include:
    * source_name: (string) name of the source
    * File: (string) file path of the matrix
* size_var
    * Optional size term definition
    * Must include
    * Name: Name of the size term table source
    * Field: Field that contains the size term
    * Note, internally a log() term is applied to this term.
* shadow_price_spec
    * Option array for shadow pricing iterations
    * Array must include:
        * attractions_source: (string) name of source that contains the attractions to match.
                                Should be present in list of tables
        * attractions_field: (string) Field name containing attractions
        * iterations: (int) Max number of shadow price iterations (Default value: 3)
        * rmse_tolerance: (real) Tolerance (RMSE%) between simulated and observed attraction vectors (Default value: 10%)
        * sp_source: (string) name of sourece that contains the Shadow price file
                        Should be present in list of tables
        * sp_field: (string) Field in shadow price file that will be updated
* productions_spec
    * Option array containing productions table and field to compute DC trips
    * Valid only for aggregate DC
    * Required if shadow price is done along with aggregate DC
    * Array must contain
    * productions_source: (string) name of source that contains the productions.
                            Should be present in list of tables
    * productions_field: (string) Field name containing productions 
*/

Class "NestedDC" (ClassOpts)
    init do
        // Check input options
        if ClassOpts.output_dir = null then Throw("NestedDC: 'output_dir' is null")
        if ClassOpts.trip_type = null then Throw("NestedDC: 'trip_type' is null")
        if ClassOpts.zone_utils = null then Throw("NestedDC: 'zone_utils' is null")
        if ClassOpts.cluster_data = null then Throw("NestedDC: 'cluster_data' is null")
        if ClassOpts.primary_spec = null then Throw("NestedDC: 'primary_spec' is null")
        if ClassOpts.dc_spec = null then Throw("NestedDC: 'dc_spec' is null")
        if ClassOpts.cluster_equiv_spec = null then Throw("NestedDC: 'cluster_equiv_spec' is null")
        if ClassOpts.tables = null then Throw("NestedDC: 'tables' is null")
        if ClassOpts.matrices = null then Throw("NestedDC: 'matrices' is null")

        // Create additional class options
        self.ClassOpts = CopyArray(ClassOpts)
        
        // Determine if model is aggregate or disaggregate
        self.ClassOpts.Aggregate = self.IsModelAggregate()

        // Some basic validity checks
        spSpec = self.ClassOpts.shadow_price_spec
        pSpec = self.ClassOpts.productions_spec
        if self.ClassOpts.Aggregate and spSpec <> null and pSpec = null then
            Throw("NestedDC: Please provide option 'productions_source' in order to perform shadow pricing.")

        if spSpec <> null then do
            attrSrc = self.ClassOpts.tables.(spSpec.attractions_source)
            if attrSrc = null then
                Throw("NestedDC: Attractions Source provided in 'shadow_price_spec' does not exist in list of 'tables' sources")
        end

        if pSpec <> null then do
            pSrc = self.ClassOpts.tables.(pSpec.productions_source)
            if pSrc = null then
                Throw("NestedDC: Productions Source provided in 'productions_spec' does not exist in list of 'tables' sources")
        end

        // Model tag
        tag = ClassOpts.trip_type
        if ClassOpts.segment <> null then
            tag = tag + "_" + ClassOpts.segment
        if ClassOpts.period <> null then
            tag = tag + "_" + ClassOpts.period
        self.ClassOpts.model_tag = tag

        // Process cluster data. Returns array of named vectors.
        self.ClassOpts.ClusterVecs = self.ProcessClusterInfo()

        // Process zone utils if string (i.e. file), else retain it
        if TypeOf(ClassOpts.zone_utils) = "string" then
            self.ClassOpts.zone_utils = self.ImportChoiceSpec(ClassOpts.zone_utils)

        self.CreateOutputFolders()

        // Create Intra Cluster Matrix
        // Create person by cluster matrix to store logsum vectors for each cluster
        // Initialize and fill the IntraCluster matrix
        // Create a table with cluster ASCs
        // Assign/update class variables accordingly
        if !self.ClassOpts.Aggregate then
            self.DisaggModelPreprocess()
    enditem


    // Export choices table to output file
    // Close all table and matrix objects
    done do
        if !self.ClassOpts.Aggregate then do
            // Export choices file to output
            choicesObj = self.ClassOpts.ChoicesTable
            vwC = choicesObj.GetView()
            if vwC <> null then
                CloseView(vwC)
            choicesObj = null

            // Close updated primary view if one was created during the process
            if self.ClassOpts.PrimaryTableModified then do
                pSpec = self.ClassOpts.primary_spec
                primarySrcName = pSpec.Name
                pSource = self.ClassOpts.tables.(primarySrcName)
                vwP = pSource.View
                if vwP <> null then
                    CloseView(vwP)
            end

            // Export In-Memory logsum to output matrix
            outName = self.ClassOpts.logsum_dir + "/PersonLogsum.mtx"
            lsObj = self.ClassOpts.LogsumMatrix
            matOpts = {"File Name": outName, Type: "Double", Label: "Logsum matrix (Person by Cluster)"}
            mNew = CopyMatrix(lsObj.GetCore("Logsum"), matOpts)
            mNew = null
            lsObj = null
            //lsObj.SaveMatrix(outName)
            
            ascObj = self.ClassOpts.ASCTable
            vwASC = ascObj.GetView()
            if vwASC <> null then
                CloseView(vwASC)
            ascObj = null

            self.ClassOpts.IntraClusterMatrix = null
        end
    endItem


    /*
        Determine if model is aggregate or disaggregate
        Disaggreate model will have a table as the primary source as opposed to a matrix
        Set appropriate class variable accordingly
    */
    Macro "IsModelAggregate" do
        aggregate = True
        primary_src_name = self.ClassOpts.primary_spec.Name
        tableSrcNames = self.ClassOpts.tables.Map(do (f) Return(f[1]) end)
        if tableSrcNames.position(primary_src_name) > 0 then
            aggregate = False
        
        // Also make sure the primary source name is valid
        mtxSrcNames = self.ClassOpts.matrices.Map(do (f) Return(f[1]) end)
        if mtxSrcNames.position(primary_src_name) = 0 and aggregate then
            Throw("NestedDC: Name of source provided in 'primary_spec' is undefined")
        
        Return(aggregate)
    enditem 


    private macro "CreateOutputFolders" do
        outputDir = self.ClassOpts.output_dir    
        self.ClassOpts.temp_dir = outputDir + "/temp"
        self.ClassOpts.mdl_dir = outputDir + "/modelfiles"
        self.ClassOpts.prob_dir = outputDir + "/probabilities"
        self.ClassOpts.logsum_dir = outputDir + "/logsums"
        self.ClassOpts.util_dir = outputDir + "/utilities"
        self.ClassOpts.choices_dir = outputDir + "/choices"
        self.ClassOpts.trips_dir = outputDir + "/trips"

        // Create output subdirectories
        mdl_dir = self.ClassOpts.mdl_dir
        if GetDirectoryInfo(mdl_dir, "All") = null then 
            CreateDirectory(mdl_dir)
        logsum_dir = self.ClassOpts.logsum_dir
        if GetDirectoryInfo(logsum_dir, "All") = null then 
            CreateDirectory(logsum_dir)
        
        if self.ClassOpts.Aggregate then do
            prob_dir = self.ClassOpts.prob_dir
            if GetDirectoryInfo(prob_dir, "All") = null then 
                CreateDirectory(prob_dir)
            util_dir = self.ClassOpts.util_dir
            if GetDirectoryInfo(util_dir, "All") = null then 
                CreateDirectory(util_dir)
            trips_dir = self.ClassOpts.trips_dir
            if self.ClassOpts.productions_spec <> null and GetDirectoryInfo(trips_dir, "All") = null then 
                CreateDirectory(trips_dir) 
            if self.ClassOpts.calc_final_prob = null then 
                self.ClassOpts.calc_final_prob = 1
        end
        else do
            temp_dir = self.ClassOpts.temp_dir
            if GetDirectoryInfo(temp_dir, "All") = null then 
                CreateDirectory(temp_dir)
            choices_dir = self.ClassOpts.choices_dir
            if GetDirectoryInfo(choices_dir, "All") = null then 
                CreateDirectory(choices_dir)
        end
    endItem


    /*
        A disaggregate model will need four sources
        - A table source with list of Person IDs and a field for the simulated (chosen) cluster
        - A Person by Cluster logsum matrix to store cluster logsums in each column
        - A table with cluster IDs and ASCs values for each cluster
        - An IntraCluster to IntraCluster matrix for the intracluster dummies or cluster to cluster constants if any.
          The IntraCluster matrix will be used to specify destinations for the cluster level model.
    */
    private macro "DisaggModelPreprocess" do
        // Build cluster indices on the destinations source
        destSrc = self.ClassOpts.dc_spec.DestinationsSource
        mtxSrcs = self.ClassOpts.matrices
        mtx = CreateObject("Matrix", mtxSrcs.(destSrc).File)
        self.CreateClusterIndices(mtx)
        mtx = null
        
        self.ProcessPrimaryTable() // Creates output choices table and copy of primary (if main primary spec has a filter)
        self.CreateLogsumMatrix(self.ClassOpts.ChoicesTable)
        self.CreateICMatrix()
        self.CreateASCTable()
    enditem


    /* 
        1. Create table with person ID and fields for the cluster logsums.
        Add a field for the origin cluster and populate
        Add a field for the simulated cluster choice

        2. Export relevant records from zonal primary spec to new in-memory view
        This is done to make the zonal level model (applied to each cluster) run faster without need for selection sets each time
    */
    private macro "ProcessPrimaryTable" do
        pSpec = self.ClassOpts.primary_spec
        primarySrcName = pSpec.Name
        pSource = self.ClassOpts.tables.(primarySrcName)
        if pSource.File <> null and pSource.View <> null then
            Throw("NestedDC: Each source specified in 'tables' should only contain 'View' or 'File' option and not both")
        
        if pSource.File <> null then
            pSpecObj = CreateObject("Table", pSource.File)
        else
            pSpecObj = CreateObject("Table", pSource.View)

        setName = null
        if pSpec.Filter <> null then do
            setName = "__Chosen"
            n = pSpecObj.SelectByQuery({Query: pSpec.Filter, SetName: setName})
            if n = 0 then
                Throw("NestedDC: 'primary_spec' 'Filter' option does not select any records")
            
            vwPrimary = ExportView(pSpecObj.GetView() + "|" + setName, "MEM", "PrimaryTable",,)
            pSourceUpdated = self.ClassOpts.tables.(primarySrcName)
            pSourceUpdated.File = null
            pSourceUpdated.View = vwPrimary
            self.ClassOpts.PrimaryTableModified = 1

            // Remove filter spec in primary
            self.ClassOpts.primary_spec.Filter = null
        end

        // Export data to the output cluster choices table
        vwM = ExportView(pSpecObj.GetView() + "|" + setName, "MEM", "ChoicesTable", {pSource.IDField, pSpec.OField}, )
        chObj = CreateObject("Table", vwM)
        newFlds = {{FieldName: "OrigCluster", Type: "integer"},
                   {FieldName: "DestCluster", Type: "integer"},
                   {FieldName: "_DestZoneID", Type: "integer"}}
        chObj.AddFields({Fields: newFlds})
        chObj.RenameField({FieldName: pSource.IDField, NewName: "_PersonID"})
        chObj.RenameField({FieldName: pSpec.OField, NewName: "_OriginZoneID"})

        // Fill Orig Cluster field using origin zone data and cluster equivalency table
        equiv_spec = self.ClassOpts.cluster_equiv_spec
        tmpObj = CreateObject("Table", equiv_spec.File)
        joinObj = chObj.Join({Table: tmpObj, LeftFields: {"_OriginZoneID"}, RightFields: {equiv_spec.ZoneIDField}})
        joinObj.OrigCluster = joinObj.(equiv_spec.ClusterIDField)
        joinObj = null
        tmpObj = null
        pSpecObj = null
        self.ClassOpts.ChoicesTable = chObj
    enditem


    /*
        Create Person by Cluster matrix that will store cluster specific logsums (in columns).
    */
    private macro "CreateLogsumMatrix"(chObj) do
        clusterVecs = self.ClassOpts.ClusterVecs
        arrClusters = v2a(clusterVecs.Cluster)
        arrPersons = v2a(chObj.[_PersonID]) 

        obj = CreateObject("Matrix", {Empty: True})
        tmpFName = GetTempPath() + "PersonLogsum.mtx"  // self.ClassOpts.logsum_dir + "/PersonLogsum.mtx"
        obj.SetMatrixOptions({Compressed: 1, DataType: "double", MatrixLabel: "Person-Cluster Logsum Matrix"})
        obj.MatrixFileName = tmpFName
        opts = {RowIDs: arrPersons, ColIDs: arrClusters, MatrixNames: {"Logsum"}, RowIndexName: "Persons", ColIndexName: "Cluster"}
        mat = obj.CreateFromArrays(opts)
        mat = null

        matm = obj.CloneMatrixStructure({MatrixLabel: "Person to Cluster Logsum Matrix", CloneSource: {tmpFName}, MemoryOnly: true})
        mObj = CreateObject("Matrix", matm)
        self.ClassOpts.LogsumMatrix = mObj
    enditem


    /*
        Create intra cluster to intra cluster matrix. Populate with IC values
    */
    private macro "CreateICMatrix" do
        clusterVecs = self.ClassOpts.ClusterVecs
        arrClusters = v2a(clusterVecs.Cluster)
        obj = CreateObject("Matrix", {Empty: True}) 
        obj.SetMatrixOptions({Compressed: 1, DataType: "double", MatrixLabel: "Cluster to Cluster Matrix"})
        obj.MatrixFileName = self.ClassOpts.temp_dir + "/ClusterToCluster.mtx"
        opts = {RowIDs: arrClusters, ColIDs: arrClusters, MatrixNames: {"Constants"}, RowIndexName: "Cluster", ColIndexName: "Cluster"}
        mat = obj.CreateFromArrays(opts)
        mObj = CreateObject("Matrix", mat)
        mObj.Constants := 0
        vIC = clusterVecs.IC + clusterVecs.Calibrated_DeltaIC
        mObj.SetVector({Core: "Constants", Vector: vIC, Diagonal: 1})
        self.ClassOpts.IntraClusterMatrix = mObj
    endItem


    /*
        Create table with cluster and ASC col
    */
    private macro "CreateASCTable" do
        clusterVecs = self.ClassOpts.ClusterVecs
        fldSpec = {{"Cluster", "Integer", 8, null, "Yes"},
                   {"ASC", "Real", 12, 2, "No"}}
        vwTmp = CreateTable("ClusterData",, "MEM", fldSpec)
        AddRecords(vwTmp,,,{"Empty Records": clusterVecs.Cluster.length})
        clusterDataObj = CreateObject("Table", vwTmp)
        clusterDataObj.Cluster = clusterVecs.Cluster
        clusterDataObj.ASC = clusterVecs.ASC + clusterVecs.Calibrated_DeltaASC
        self.ClassOpts.ASCTable = clusterDataObj
    endItem


    /*
        Creates shadow price table with zone id field and shaow prices
        Set initial shadow prices to 0
    */
    private macro "InitializeShadowPrices" do
        equiv_spec = self.ClassOpts.cluster_equiv_spec
        obj = CreateObject("Table", equiv_spec.File)
        v = obj.(equiv_spec.ZoneIDField)

        // Create table with zone IDs and shadow prices
        fldSpec = {{"ZoneID", "Integer", 8, null, "Yes"},
                   {"ShadowPrice", "Real", 12, 2, "No"}}
        vwSP = CreateTable("ShadowPriceTable",, "MEM", fldSpec)
        AddRecords(vwSP,,,{"Empty Records": v.length})
        objSP = CreateObject("Table", vwSP)
        objSP.ZoneID = v
        objSP.ShadowPrice = 0
        self.ClassOpts.ShadowPriceTable = objSP
    endItem


    Macro "Run" do
        // Check if shadow pricing needs to be done
        spSpec = self.ClassOpts.shadow_price_spec
        if spSpec = null then
            self.RunDC()
        else do
            iters = spSpec.iterations
            if iters = null then 
                iters = 3 // Default
            pbar1 = CreateObject("G30 Progress Bar", "DC Shadow Price Iterations...", false, iters)
            for i = 1 to iters do
                // Run Model
                self.RunDC()

                // Tabulate output choices
                outObj = self.TabulateChoices()

                // Compute Shadow Prices, update SP table and check for convergence
                convergence = self.UpdateShadowPrices(outObj)
                CloseView(outObj.GetView())
                outObj = null
                
                if convergence then 
                    break
                pbar1.Step()
            end
            pbar1.Destroy()
        end
    enditem


    Macro "RunDC" do
        if self.ClassOpts.Aggregate then
            self.RunAggregateDC()
        else
            self.RunDisaggregateDC()
    endItem


    private macro "RunAggregateDC" do        
        // Run zone-level DC
        runOpts = self.SetAggZoneOpts()
        self.RunChoiceModel(runOpts)
        
        // Build cluster-level choice data
        self.BuildClusterData()

        // Run cluster-level model
        runOpts = self.SetAggClusterOpts()
        self.RunChoiceModel(runOpts)

        // Combine cluster- and zone-level probabilities into final results
        if self.ClassOpts.calc_final_prob = 1 or self.ClassOpts.productions_spec <> null then
            self.CalcFinalProbs()

        if self.ClassOpts.productions_spec <> null then
            self.ComputeTrips()
    enditem


    private macro "SetAggZoneOpts" do
        tag = self.ClassOpts.model_tag
        
        runOpts = null
        runOpts.Tag = tag
        runOpts.Utility = self.ClassOpts.zone_utils
        runOpts.DCSpec = self.ClassOpts.dc_spec
        runOpts.PrimarySpec = self.ClassOpts.primary_spec
        runOpts.TableSources = self.ClassOpts.tables
        runOpts.MatrixSources = self.ClassOpts.matrices
        runOpts.OutputModelFile = self.ClassOpts.mdl_dir + "\\" + tag + "_zone.dcm"
        runOpts.OutputSpec = {Probability: self.ClassOpts.prob_dir + "\\probability_" + tag + "_zone.mtx",
                                Utility: self.ClassOpts.util_dir + "\\utility_" + tag + "_zone.mtx"}
        if self.ClassOpts.zone_util_subs <> null then
            runOpts.UtilitySubs = self.ClassOpts.zone_util_subs
        if self.ClassOpts.zone_availabilities <> null then
           runOpts.ZoneAvailabilities = self.ClassOpts.zone_availabilities
        if self.ClassOpts.size_var <> null then
            runOpts.SizeVar = self.ClassOpts.size_var
        Return(runOpts)
    enditem


    private macro "SetAggClusterOpts" do
        tag = self.ClassOpts.model_tag
        
        cluster_utils = null
        cluster_utils.Expression = {"LogsumMtx.asc", "LogsumMtx.ic", "LogsumMtx.logsum"}
        cluster_utils.Coefficient = {1.0, 1.0, 1.0}
        cluster_utils.Description = {"Cluster ASC", "Cluster IntraCounty", "Zonal Logsum"}

        runOpts = null
        runOpts.Tag = tag
        runOpts.Utility = cluster_utils
        runOpts.DCSpec = ({DestinationsSource: "LogsumMtx", DestinationsIndex: "Col_AggregationID"})
        runOpts.PrimarySpec = ({Name: "LogsumMtx"})
        runOpts.MatrixSources.LogsumMtx = {File: self.ClassOpts.logsum_dir + "\\agg_zonal_ls_" + tag + ".mtx"}
        runOpts.OutputSpec = {Probability: self.ClassOpts.prob_dir + "\\probability_" + tag + "_cluster.mtx",
                                Utility: self.ClassOpts.util_dir + "\\utility_" + tag + "_cluster.mtx"}
        runOpts.OutputModelFile = self.ClassOpts.mdl_dir + "\\" + tag + "_cluster.dcm"
        Return(runOpts)
    enditem

    
    private macro "RunDisaggregateDC" do
        clusterVecs = self.ClassOpts.ClusterVecs
        vClusters = clusterVecs.Cluster
        vClusterNames = clusterVecs.ClusterName
        vThetas = clusterVecs.Theta

        // Run loop over clusters and evaluate zonal model for each cluster (with alternatives being the zones belonging to that cluster)
        pbar = CreateObject("G30 Progress Bar", "Running Lower Level DC models...", false, vClusters.length)
        for i = 1 to vClusters.length do
            clusterInfo = {Cluster: vClusters[i], ClusterName: vClusterNames[i], Theta: vThetas[i]}
            runOpts = self.SetDisaggZoneOpts(clusterInfo)

            // Run zonal model
            self.RunChoiceModel(runOpts)

            // Update logsum matrix column
            self.UpdateLogsumMatrix(clusterInfo)
            pbar.Step()
        end
        pbar.Destroy()

        // Build and run cluster level model
        runOpts = self.SetDisaggClusterOpts()
        self.RunChoiceModel(runOpts)

        // Simulate final choices at the zone level
        self.SimulateChoices()
    endItem


    private macro "SetDisaggZoneOpts"(opts) do
        clusterName = opts.ClusterName
        theta = opts.Theta
        tag = self.ClassOpts.model_tag + "_" + clusterName
        dc_spec = self.ClassOpts.dc_spec
        
        runOpts = null
        runOpts.Tag = tag
        runOpts.Utility = self.ScaleZonalUtility(theta)
        runOpts.DCSpec = ({DestinationsSource: dc_spec.DestinationsSource, DestinationsIndex: clusterName})
        runOpts.PrimarySpec = self.ClassOpts.primary_spec
        runOpts.TableSources = self.ClassOpts.tables
        runOpts.MatrixSources = self.ClassOpts.matrices
        runOpts.OutputSpec = {ChoicesTable: self.ClassOpts.choices_dir + "\\Choices_" + tag + ".bin",
                                LogsumTable: self.ClassOpts.logsum_dir + "\\Logsums_" + tag + ".bin"}
        runOpts.OutputModelFile = self.ClassOpts.mdl_dir + "\\" + tag + ".dcm"
        runOpts.RandomSeed = nz(self.ClassOpts.random_seed) + opts.Cluster*100
        if self.ClassOpts.zone_util_subs <> null then
           runOpts.UtilitySubs = self.ClassOpts.zone_util_subs
        if self.ClassOpts.zone_availabilities <> null then
           runOpts.ZoneAvailabilities = self.ClassOpts.zone_availabilities
        if self.ClassOpts.size_var <> null then
            runOpts.SizeVar = self.ClassOpts.size_var
        Return(runOpts)
    enditem


    private macro "SetDisaggClusterOpts" do
        tag = self.ClassOpts.model_tag
        lsObj = self.ClassOpts.LogsumMatrix
        
        cluster_utils = null
        cluster_utils.Expression = {"LogsumMtx.Logsum", "IntraClusterMtx.Constants", "ClusterData.ASC.D"}
        cluster_utils.Coefficient = {1.0, 1.0, 1.0}
        cluster_utils.Description = {"Zone Logsums", "IntraCluster Constants", "Cluster ASC"}
        
        runOpts = null
        runOpts.Tag = tag
        runOpts.Utility = cluster_utils
        runOpts.DCSpec = ({DestinationsSource: "IntraClusterMtx", DestinationsIndex: "Cluster"})
        runOpts.PrimarySpec = ({Name: "ChoicesTable", OField: "OrigCluster"})
        runOpts.MatrixSources.LogsumMtx = {Handle: lsObj.GetMatrixHandle(), PersonBased: 1}
        runOpts.MatrixSources.IntraClusterMtx = {File: self.ClassOpts.temp_dir + "\\ClusterToCluster.mtx"}
        runOpts.TableSources.ChoicesTable = {View: self.ClassOpts.ChoicesTable.GetView(), IDField: "_PersonID"}
        runOpts.TableSources.ClusterData = {View: self.ClassOpts.ASCTable.GetView(), IDField: "Cluster"}
        runOpts.OutputSpec = {ChoicesField: "DestCluster"}
        runOpts.OutputModelFile = self.ClassOpts.mdl_dir + "\\" + tag + "_cluster.dcm"
        runOpts.RandomSeed = nz(self.ClassOpts.random_seed)
        Return(runOpts)
    enditem


    private macro "ScaleZonalUtility"(theta) do
        new_util = CopyArray(self.ClassOpts.zone_utils)
        arrCoeffs = new_util.Coefficient
        scaledCoeffs = arrCoeffs.Map(do (f) Return(f/theta) end)
        new_util.Coefficient = CopyArray(scaledCoeffs)
        Return(new_util)
    enditem


    private macro "UpdateLogsumMatrix"(opts) do
        // Get logsum vector
        cluster = opts.Cluster
        clusterName = opts.ClusterName
        theta = opts.Theta
        tag = self.ClassOpts.model_tag + "_" + clusterName
        lsFile = self.ClassOpts.logsum_dir + "\\Logsums_" + tag + ".bin"
        tmpObj = CreateObject("Table", lsFile)
        {idFld, lsFld} = tmpObj.GetFieldNames()
        tmpObj.Sort({FieldArray: {{idFld, "Ascending"}}})
        vLS = tmpObj.(lsFld)
        vLS = zn(vLS,)  // If sum(exp(u)) is zero for all zones in a cluster, then top level model should not choose this cluster

        // Set vector in matrix
        mObj = self.ClassOpts.LogsumMatrix
        mObj.SetVector({Core: "Logsum", Vector: vLS*theta, Column: cluster})
    enditem


    /*
        Macro that aggregates the output choices
        Used for computation of shadow prices
    */
    private macro "TabulateChoices" do
        tag = self.ClassOpts.model_tag
        if !self.ClassOpts.Aggregate then do
            chObj = self.ClassOpts.ChoicesTable
            flds = {{"_DestZoneID", "COUNT",}}
            vwAgg = AggregateTable("AggrChoices", chObj.GetView() + "|", "MEM",,"_DestZoneID", flds,)
        end
        else do
            totalsMtx = self.ClassOpts.trips_dir + "/DC_Trips_" + tag + ".mtx"
            mObj = CreateObject("Matrix", totalsMtx)
            vwAgg = ExportMatrix(mObj.GetCore("Trips"),, "Columns", "MEM", "AggrChoices", {{"Marginal", "Sum"}})
            mObj = null
        end
        aggObj = CreateObject("Table", vwAgg)
        flds = aggObj.GetFieldNames()
        aggObj.RenameField({FieldName: flds[1], NewName: "_AggregationZoneID"})
        aggObj.RenameField({FieldName: flds[2], NewName: "_SimulatedCount"})
        Return(aggObj)
    endItem


    /*
        Macro that updates shadow prices
    */
    private macro "UpdateShadowPrices"(aggObj) do
        sp_spec = self.ClassOpts.shadow_price_spec
        tolerance = sp_spec.rmse_tolerance
        if tolerance = null then
            tolerance = 10  // Default

        // Open attractions source
        aSrc = sp_spec.attractions_source
        attr_src = self.ClassOpts.tables.(aSrc)
        if attr_src.File <> null then
            attrObj = CreateObject("Table", attr_src.File)
        else
            attrObj = CreateObject("Table", attr_src.View)
        
        // Open sp source
        spSrc = sp_spec.sp_source
        sp_src = self.ClassOpts.tables.(spSrc)
        if spSrc <> aSrc then do
            if sp_src.File <> null then
                spObj = CreateObject("Table", sp_src.File)
            else
                spObj = CreateObject("Table", sp_src.View)
        end
        else
            spObj = attrObj

        // Join sp source with aggregated choices and then to the attractions source
        objJ1 = spObj.Join({Table: aggObj, LeftFields: {sp_src.IDField}, RightFields: {"_AggregationZoneID"}})
        if spSrc <> aSrc then
            objJ2 = objJ1.Join({Table: attrObj, LeftFields: {"_AggregationZoneID"}, RightFields: {attr_src.IDField}})
        else
            objJ2 = objJ1
        vSim = objJ2.[_SimulatedCount]
        vTarget = objJ2.(sp_spec.attractions_field)

        // Check RMSE between simulated and observed. Return if tolerance is met or update shadow prices if not.
        o = CreateObject("Model.Statistics")
        stats = o.rmse({Method: "vectors", Predicted: vSim, Observed: vTarget})
        prmse = stats.RelRMSE
        if prmse <= tolerance then
            convergence = 1
        else do // Adjust SP values
            convergence = 0
            vCorr = if vSim > 0 and vTarget > 0 then 0.75*log(vTarget/vSim) else 0.0
            sp = sp_spec.sp_field
            objJ2.(sp) = nz(objJ2.(sp)) + vCorr
        end
        objJ2 = null
        objJ1 = null
        spObj = null
        attrObj = null
        Return(convergence)
    endItem


    /*
    Generic choice model calculator.

    Inputs (other than Class inputs)
    * RunOpts (changes based on whether run is aggregate/disaggregate and whether the model is at the zone/cluster level)
        - Utility
        - DCSpec
        - PrimarySpec
        - MatrixSources
        - TableSources
        - OutputSpec
        - OutputModelFile
        - UtilitySubs
        - SizeVar
    */
    Macro "RunChoiceModel"(runOpts) do
        // Set up and run model
        obj = CreateObject("PMEChoiceModel", {ModelName: runOpts.Tag})
        if self.ClassOpts.segment <> null then
            obj.Segment = self.ClassOpts.segment
        
        if runOpts.RandomSeed <> null then
            obj.RandomSeed = runOpts.RandomSeed

        // Add sources
        tables = runOpts.TableSources
        for i = 1 to tables.length do
            source_name = tables[i][1]
            source = tables.(source_name)
            tSrcOpts = {SourceName: source_name, IDField: source.IDField, JoinSpec: source.JoinSpec}
            if source.File <> null then
                tSrcOpts.File = source.File
            else if source.View <> null then
                tSrcOpts.View = source.View
            else
                Throw("Nested DC: Error in table source definition for " + source_name)

            obj.AddTableSource(tSrcOpts)
        end

        matrices = runOpts.MatrixSources
        for i = 1 to matrices.length do
            source_name = matrices[i][1]
            source = matrices.(source_name)

            mSrcOpts = {SourceName: source_name}
            if source.File <> null then
                mSrcOpts.File = source.File
            else if source.Handle <> null then
                mSrcOpts.Handle = source.Handle
            else
                Throw("Nested DC: Error in matrix source definition for " + source_name)
            
            if source.RowIndex <> null then
                mSrcOpts.RowIndex = source.RowIndex
            if source.ColIndex <> null then
                mSrcOpts.ColIndex = source.ColIndex
            if source.PersonBased = 1 then
                mSrcOpts.PersonBased = 1
            obj.AddMatrixSource(mSrcOpts)
        end

        // Add alternatives, utility and specify the primary source
        obj.OutputModelFile = runOpts.OutputModelFile
        obj.AddPrimarySpec(runOpts.PrimarySpec)
        obj.AddDestinations(runOpts.DCSpec)
        
        utilSpec = {UtilityFunction: runOpts.Utility}
        if runOpts.UtilitySubs <> null then
            utilSpec.[Substitute Strings] = runOpts.UtilitySubs
        if runOpts.ZoneAvailabilities <> null then
            utilSpec.AvailabilityExpressions = runOpts.ZoneAvailabilities
        obj.AddUtility(utilSpec)
        
        if runOpts.SizeVar <> null then
            obj.AddSizeVariable(runOpts.SizeVar)

        obj.AddOutputSpec(runOpts.OutputSpec)
        ret = obj.Evaluate()
        if !ret then
            Throw("Running mode choice model failed for: " + runOpts.Tag)
        obj = null
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
    Aggregates the DC logsums into cluster-level values.
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
        tag = self.ClassOpts.model_tag

        // Collect vectors of cluster names, IDs, and theta values
        clusterVecs = self.ClassOpts.ClusterVecs
        v_cluster_ids = clusterVecs.Cluster
        v_cluster_names = clusterVecs.ClusterName
        v_cluster_theta = clusterVecs.Theta
        v_cluster_asc = clusterVecs.ASC
        v_cluster_ic = clusterVecs.IC
        v_additional_asc = clusterVecs.Calibrated_DeltaASC
        v_additional_ic = clusterVecs.Calibrated_DeltaIC

        mtx_file = util_dir + "/utility_" + tag + "_zone.mtx"
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
            Matrix: {FileName: logsum_dir + "/agg_zonal_ls_" + tag + ".mtx", MatrixLabel: "Cluster Logsums"},
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
        agg.AddCores({"LnSumExpScaledTotal", "logsum", "ic", "asc"})
        cores = agg.GetCores()
        cores.LnSumExpScaledTotal := Log(cores.[Sum of ExpScaledTotal])
        cores.logsum := cores.LnSumExpScaledTotal * v_cluster_theta
        cores.ic := if nz(cores.[Sum of IntraCluster]) > 0 then 1 else 0
        cores.ic := cores.ic * (v_cluster_ic + v_additional_ic)
        cores.asc := v_cluster_asc + v_additional_asc
    enditem


    // Collect vectors of cluster names, IDs, ASC, IC and theta values
    // Return vectors that will be stored with the class data
    // Called during init
    private macro "ProcessClusterInfo" do
        cluster_data = self.ClassOpts.cluster_data
        if TypeOf(cluster_data)  = "string" then do
            theta_vw = OpenTable("thetas", "CSV", {cluster_data})
            
            {flds, specs} = GetFields(theta_vw,)
            vecOpts.[Sort Order] = {{"Cluster", "Ascending"}}
            vecOpts.OptArray = 1
            clusterVecs = GetDataVectors(theta_vw + "|", flds, vecOpts)
            CloseView(theta_vw)
        end
        else do
            clusterVecs = null
            for i = 1 to cluster_data.length do
                colName = cluster_data[i][1]
                clusterVecs.(colName) = a2v(cluster_data[i][2])
            end
        end

        // Check required cols
        req_cols = {"Cluster", "ClusterName", "Theta", "ASC", "IC"}
        for col in req_cols do
            if TypeOf(clusterVecs.(col)) <> 'vector' then
                Throw(printf("Field or column '%s' missing in cluster data spec", {col}))
        end
        
        // Fill missing thetas with 1 and missing constants to 0
        clusterVecs.ASC = nz(clusterVecs.ASC)
        clusterVecs.IC = nz(clusterVecs.IC)
        clusterVecs.Theta = if clusterVecs.Theta = null then 1.0 else clusterVecs.Theta
        
        // Check optional cols
        if TypeOf(clusterVecs.Calibrated_DeltaASC) <> 'vector' then
            clusterVecs.Calibrated_DeltaASC = Vector(clusterVecs.Cluster.Length, "Float", {Constant: 0.0})
        else
            clusterVecs.Calibrated_DeltaASC = nz(clusterVecs.Calibrated_DeltaASC)
        
        if TypeOf(clusterVecs.Calibrated_DeltaIC) <> 'vector' then
            clusterVecs.Calibrated_DeltaIC = Vector(clusterVecs.Cluster.Length, "Float", {Constant: 0.0})
        else
            clusterVecs.Calibrated_DeltaIC = nz(clusterVecs.Calibrated_DeltaIC)    
        
        Return(clusterVecs)
    enditem

    /*
    Creates indices that can be used to select the zones in each cluster
    */
    Macro "CreateClusterIndices"(mtx) do
        equiv_spec = self.ClassOpts.cluster_equiv_spec
        clusterVecs = self.ClassOpts.ClusterVecs
        v_cluster_ids = clusterVecs.Cluster
        v_cluster_names = clusterVecs.ClusterName

        for i = 1 to v_cluster_ids.length do
            cluster_id = v_cluster_ids[i]
            cluster_name = v_cluster_names[i]

            mtx.AddIndex({
                Matrix: mtx.GetMatrixHandle(),
                IndexName: cluster_name,
                Filter: printf("%s = %u", {equiv_spec.ClusterIDField, cluster_id}),
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
    1 within each cluster. This method applies only for the aggregate DC case.
    */
    Macro "CalcFinalProbs" do
        trip_type = self.ClassOpts.trip_type
        period = self.ClassOpts.period
        prob_dir = self.ClassOpts.prob_dir
        tag = self.ClassOpts.model_tag
        
        cluster_file = prob_dir + "/probability_" + tag + "_cluster.mtx"
        zone_file = prob_dir + "/probability_" + tag + "_zone.mtx"
        z_mtx = CreateObject("Matrix", zone_file)
        c_mtx = CreateObject("Matrix", cluster_file)
        
        clusterVecs = self.ClassOpts.ClusterVecs
        v_cluster_ids = clusterVecs.Cluster
        v_cluster_names = clusterVecs.ClusterName

        // Add cluster indices to the zonal matrix
        self.CreateClusterIndices(z_mtx)
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
    enditem


    /*
        Multiply final prob matrix by productions to create DC trip matrix
    */
    macro "ComputeTrips" do
        prob_dir = self.ClassOpts.prob_dir
        trips_dir = self.ClassOpts.trips_dir
        tag = self.ClassOpts.model_tag
        prob_file = prob_dir + "/probability_" + tag + "_zone.mtx"
        trips_file = trips_dir + "/DC_Trips_" + tag + ".mtx"
        pObj = CreateObject("Matrix", prob_file)
        
        // Create output totals
        mOpts = {FileName: trips_file, Tables:  {"Trips"}, Label: tag + " Trips"}
        mat = CopyMatrixStructure({pObj.GetCore(1)}, mOpts)
        mObj = CreateObject("Matrix", mat)

        // Open productions source and get productions vector
        pSpec = self.ClassOpts.productions_spec
        src = pSpec.productions_source
        prod_src = self.ClassOpts.tables.(src)
        if prod_src.File <> null then
            prodObj = CreateObject("Table", prod_src.File)
        else
            prodObj = CreateObject("Table", prod_src.View)
        prodFld = pSpec.productions_field
        vP = nz(prodObj.(prodFld))
        prodObj = null

        // Compute trips
        vP.ColumnBased = "True"
        mObj.Trips := pObj.final_prob * vP
        pObj = null
        mObj = null
        m = null
    endItem

    /*
        Simulate final choices in case of a disaggregate model
        - The cluster choice has already been made at this point ('DestCluster')
        - Copy final zonal choices from the appropriate cluster specific choice table
    */
    private macro "SimulateChoices" do
        chObj = self.ClassOpts.ChoicesTable
        clusterVecs = self.ClassOpts.ClusterVecs
        vClusters = clusterVecs.Cluster
        vClusterNames = clusterVecs.ClusterName
        for i = 1 to vClusters.length do
            c = vClusters[i]

            // Select records from choices table
            n = chObj.SelectByQuery({Query: "DestCluster = " + String(c), SetName: "Cluster" + String(c)})
            if n = 0 then
                continue

            // Open choices file for appropriate cluster
            tag = self.ClassOpts.model_tag + "_" + vClusterNames[i]
            tmpObj = CreateObject("Table", self.ClassOpts.choices_dir + "\\Choices_" + tag + ".bin")
            flds = tmpObj.GetFieldNames()

            // Join and fill
            joinObj = chObj.Join({Table: tmpObj, LeftFields: {"_PersonID"}, RightFields: {flds[1]}})
            joinObj.ChangeSet({SetName: "Cluster" + String(c)})
            joinObj.[_DestZoneID] = joinObj.Destination
            joinObj = null
            tmpObj = null
        end

        // Export choices file to output
        outFile = self.ClassOpts.choices_dir + "/" + self.ClassOpts.model_tag + "_DC_Choices.bin"
        ExportView(chObj.GetView() + "|", "FFB", outFile,,)
    endItem
endclass
