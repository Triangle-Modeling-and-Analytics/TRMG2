/*
Generic MC calculator.

Inputs
  * output_dir
    * String
    * Output directory where subfolders and files will be written.
  * trip_type
    * String
    * Name of the trip type/purpose
  * util_file
    * String
    * File path of the CSV file containing utility terms
  * nest_file
    * Optional string (default: null)
    * File path of the CSV file containing nesting structure and thetas
  * period
    * Optional string (default: null)
    * Time of day. Only used for file naming, so you can use "daily", "all",
      "am", or just leave it blank.
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

Macro "MC" (MacroOpts)
    
    output_dir = MacroOpts.output_dir
    trip_type = MacroOpts.trip_type
    util_file = MacroOpts.util_file
    nest_file = MacroOpts.nest_file
    period = MacroOpts.period
    segments = MacroOpts.segments
    primary_spec = MacroOpts.primary_spec
    tables = MacroOpts.tables
    matrices = MacroOpts.matrices

    if output_dir = null then Throw("MC: 'output_dir' is null")
    if trip_type = null then Throw("MC: 'trip_type' is null")
    if util_file = null then Throw("MC: 'util_file' is null")
    if primary_spec = null then Throw("MC: 'primary_spec' is null")
    if tables = null and matrices = null 
        then Throw("MC: 'tables' and 'matrices' are both null")
    if segments = null then segments = {null}

    // Create output subdirectories
    mdl_dir = output_dir + "\\model_files"
    if GetDirectoryInfo(mdl_dir, "All") = null then CreateDirectory(mdl_dir)
    prob_dir = output_dir + "\\probabilities"
    if GetDirectoryInfo(prob_dir, "All") = null then CreateDirectory(prob_dir)
    logsum_dir = output_dir + "\\logsums"
    if GetDirectoryInfo(logsum_dir, "All") = null then CreateDirectory(logsum_dir)
    util_dir = output_dir + "\\utilities"
    if GetDirectoryInfo(util_dir, "All") = null then CreateDirectory(util_dir)

    // Import util CSV file into an options array
    util = RunMacro("Import MC Spec", util_file)
    
    if nest_file <> null then nest_tree = RunMacro("Import MC Spec", nest_file)

    for seg in segments do
        tag = trip_type
        if seg <> null then tag = tag + "_" + seg
        if period <> null then tag = tag + "_" + period

        // Set up and run model
        obj = CreateObject("PMEChoiceModel", {ModelName: tag})
        obj.Segment = seg
        
        obj.OutputModelFile = mdl_dir + "\\" + tag + ".mdl"
        
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
        if nest_tree <> null then
            obj.AddAlternatives({AlternativesTree: nest_tree})
        obj.AddUtility({UtilityFunction: util})
        obj.AddPrimarySpec(primary_spec)
        
        // Specify outputs
        output_opts = {Probability: prob_dir + "\\probability_" + tag + ".mtx",
                        Logsum: logsum_dir + "\\logsum_" + tag + ".mtx"}
        // The matrices take up a lot of space, so don't write the utility 
        // matrices except for debugging/development.
        // Uncomment the line below to write them.
        // output_opts = output_opts + {Utility: util_dir + "\\utility_" + tag + ".mtx"}
        obj.AddOutputSpec(output_opts)
        
        //obj.CloseFiles = 0 // Uncomment to leave files open, so you can save a workspace
        ret = obj.Evaluate()
        if !ret then
            Throw("Running mode choice model failed for: " + tag)
        obj = null
    end
endMacro

/*
Helper for "MC" macro
*/

Macro "Import MC Spec"(file)
    vw = OpenTable("Spec", "CSV", {file,})
    {flds, specs} = GetFields(vw,)
    vecs = GetDataVectors(vw + "|", flds, {OptArray: 1})
    
    util = null
    for fld in flds do
        util.(fld) = v2a(vecs.(fld))
    end
    CloseView(vw)
    Return(util)
endMacro