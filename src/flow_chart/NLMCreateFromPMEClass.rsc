Class "PMEChoiceModel"(opts) inherits: "TransCAD.Task"

    init do
        // Object that contains the master sources list(s)
        if opts.ModelName = null then
            self.ModelName = 'Choice'
        else
            self.ModelName = opts.ModelName
        
        if opts.SourcesObject <> null then do   // Make a copy of the sources object that was passed during instantiation.
            objArr = Serialize(opts.SourcesObject)
            self.MasterSourcesObject = DeSerialize(objArr)
        end
        else    // Create new sources object with no sources. Implies that sources will need to be added on the fly using AddTableSource() or AddMatrixSource()
            self.MasterSourcesObject = CreateObject("Choice Model Sources") // Create sources object with no arguments. (All sources will be defined on the fly)

        // Default Options
        self.RunModel = 1
        self.CloseFiles = 1
        self.isAggregateModel = 0
        self.ModelType = 'Mode Choice'
        self.ShadowIterations = 10       // Default shadow price iterations
        self.ShadowTolerance = 0.1  // Default shadow price tolerance
        self.AlternateUtilFormat = 0 // Default utility format
 
        // Outputs/Other Variables
        self.Model = null
        self.Utility = null
        self.AvailExpressions = null
        self.Substitutes = null
        self.AlternativesTree = null
        self.AlternativesTable = null
        self.Alternatives = null
        self.ASCs = null
        self.Thetas = null
        self.ModelTableSources = null
        self.ModelMatrixSources = null
        self.LeafAlts = null
        self.DestinationsSource = null
        self.DestinationsIndex = null
        self.PrimarySpec = null
        self.TotalsSpec = null
        self.OutputSpec = null
        self.SizeVariableSpec = null
        self.ShadowPriceSpec = null
        self.SegmentConstants = null
        self.Segment = null
        self.ReportShares = 0       // Default 0, set to 1 if mode choice shares summary needed
        self.ModelShares = null
        self.RandomSeed = 99991     // The largest prime number less than 100,000. Also the binary equivalent has 16 bits and no pattern among the bits.
    enditem


    done do
        self.Cleanup()
    enditem


    macro "_SetRunModel"(flag) do
        self.RunModel = flag
    endItem


    macro "_SetCloseFiles"(flag) do
        self.CloseFiles = flag
    endItem

    macro "_SetOutputModelFile"(file) do
        self.ModelFile = file
    endItem

    macro "_SetReportShares"(flag) do
        self.ReportShares = flag
    endItem

    macro "_SetRandomSeed"(seed) do
        self.RandomSeed = seed
    endItem

    macro "_SetSegment"(seg) do
        seg = self.GetStringOrNull(seg, "NLMCreateFromPME: 'Segment' attribute is not a string")
        self.Segment = Lower(seg)
    endItem

    // Macro to add matrix source not present in the sources object. Allows on the fly sources.
    macro "AddMatrixSource"(spec) do
        self.MasterSourcesObject.AddMatrixSource(spec)
    endItem

    // Macro to add table source not present in the sources object. Allows on the fly sources.
    macro "AddTableSource"(spec) do
        self.MasterSourcesObject.AddTableSource(spec)
    endItem

    macro "AddPrimarySpec"(opts) do
        opts = self.GetOptionsArray(opts, "NLMCreateFromPME: Argument passed to AddPrimarySpec() is not an option array")
        primarySrcName = self.GetString(opts.Name, "NLMCreateFromPME: 'Name' option passed to AddPrimarySpec() is either missing or is not a string")
        
        // Check if source name is present
        srcObj = self.MasterSourcesObject
        chk = srcObj.CheckSource(primarySrcName)
        if !chk then
            Throw(ErrMsg + " Source \'" + primarySrcName + "\' undefined.")
        self.PrimarySpec.Name = primarySrcName

        // Other options (will be verified further depending on other model details)
        self.PrimarySpec.Filter = self.GetStringOrNull(opts.Filter, "NLMCreateFromPME: 'Filter' option passed to AddPrimarySpec() is not a string")
        self.PrimarySpec.OField = self.GetStringOrNull(opts.OField, "NLMCreateFromPME: 'OField' option passed to AddPrimarySpec() is not a string")
        self.PrimarySpec.DField = self.GetStringOrNull(opts.DField, "NLMCreateFromPME: 'DField' option passed to AddPrimarySpec() is not a string")

        // Determine if model is aggregate or disagg
        info = srcObj.GetSourceInfo(primarySrcName)
        if info.Type = "Table" then
            self.isAggregateModel = 0
        else
            self.isAggregateModel = 1
    endItem


    macro "AddDestinations"(opts) do
        opts = self.GetOptionsArray(opts, "NLMCreateFromPME: Argument passed to AddDestinations() is not an option array")
        destSrc = self.GetString(opts.DestinationsSource, "NLMCreateFromPME: 'DestinationsSource' option passed to AddDestinations() is either missing or is not a string")
        destIdx = self.GetString(opts.DestinationsIndex, "NLMCreateFromPME: 'DestinationsIndex' option passed to AddDestinations() is either missing or is not a string")
        
        // Check Source
        srcObj = self.MasterSourcesObject
        srcInfo = srcObj.GetSourceInfo(destSrc)
        matrix = srcInfo.File
        if matrix = null then
            Throw("The Destinations Source option [" + destSrc + "] does not correspond to any argument in the flowchart (Args)")
        self.CheckFileValidity(matrix)
            
        m = OpenMatrix(matrix,)
        {ridxs, cidxs} = GetMatrixIndexNames(m)
        m = null
        cidxs = cidxs.Map(do (f) Return(Lower(f)) end)
        if ArrayPosition(cidxs, {destIdx},) = 0 then
            Throw("Column Index \''" + destIdx + "\' not found in \''" + matrix)

        self.DestinationsSource = destSrc
        self.DestinationsIndex = destIdx
        self.ModelType = "Destination Choice"
    endItem


    macro "AddOutputSpec"(opts) do
        self.CheckOptionType(opts, "array", "Argument to \'AddOutputSpec\' is not an array")
        
        // Aggregate Options
        options = {'Probability', 'Logsum', 'Utility', 'Totals'}
        for opt in options do
            optVal = opts.(opt)
            if optVal <> null then do
                agg = 1
                self.CheckOptionType(optVal, "string", "\'" + opt + "\' option in \'AddOutputSpec\' is not a string")
                self.CheckOutputFile(optVal, "mtx")
                self.OutputSpec.(opt) = optVal 
            end
        end

        // Disagg Options
        outFile = opts.ChoicesTable
        outFld = opts.ChoicesField
        probFile = opts.ProbabilityTable
        if (outFile <> null or outFld <> null) and agg then
            Throw("Cannot specify both aggregate and disaggregate options to AddOutputSpec()")
        
        // Check for disagg specs
        if !agg then do
            //if outFile = null and outFld = null then
            //    Throw("Invalid option to AddOutputSpec()")
            if outFile <> null and outFld <> null then
                Throw("Invalid option to AddOutputSpec().\n\'Specify either 1. An output file (ChoicesTable) OR 2: A field name in the primary table (ChoicesField), but not both.")
            if outFile <> null then do
                self.CheckOutputFile(outFile, "bin")
                self.OutputSpec.ChoicesTable = outFile
            end
            if outFld <> null then do
                self.CheckOptionType(outFld, "string", "\'ChoicesField\' option in \'AddOutputSpec\' is not a string")
                self.OutputSpec.ChoicesField = outFld
            end
            if probFile <> null then do
                self.CheckOptionType(probFile, "string", "\'ProbabilityTable\' option in \'AddOutputSpec\' is not a string")
                self.OutputSpec.ProbabilityTable = probFile
            end
        end
    endItem


    macro "AddTotalsSpec"(opts) do
        opts = self.GetOptionsArray(opts, "NLMCreateFromPME: Argument passed to AddTotalsSpec() is not an option array")
        totalsSrcName = self.GetString(opts.Name, "NLMCreateFromPME: 'Name' option passed to AddTotalsSpec() is either missing or is not a string")
        zonalFld = self.GetStringOrNull(opts.ZonalField, "NLMCreateFromPME: 'ZonalField' option passed to AddTotalsSpec() is not a string")
        mtxCore = self.GetStringOrNull(opts.MatrixCore, "NLMCreateFromPME: 'MatrixCore' option passed to AddTotalsSpec() is not a string")

        if mtxCore = null and zonalFld = null then
            Throw("NLMCreateFromPME: Invalid option for AddTotalsSpec()")

        if mtxCore <> null and zonalFld <> null then
            Throw("NLMCreateFromPME: Invalid option for AddTotalsSpec()")
        
        srcObj = self.MasterSourcesObject
        chk = srcObj.CheckSource(totalsSrcName)
        if !chk then
            Throw(ErrMsg + " Source \'" + totalsSrcName + "\' undefined.")
        self.TotalsSpec.Name = totalsSrcName
        
        self.TotalsSpec.MatrixCore = mtxCore
        self.TotalsSpec.ZonalField = zonalFld
    endItem


    macro "AddSizeVariable"(opts) do
        opts = self.GetOptionsArray(opts, "NLMCreateFromPME: Argument passed to AddSizeVariable() is not an option array")
        sizeSrcName = self.GetString(opts.Name, "NLMCreateFromPME: 'Name' option passed to AddSizeVariable() is either missing or is not a string")

        // Check if source name is present in master sources list
        srcObj = self.MasterSourcesObject
        chk = srcObj.GetSourceInfo(sizeSrcName)
        if chk.Type <> "Table" then
            Throw(ErrMsg + " Source \'" + sizeSrcName + "\' is not defined in the master table sources.")
        
        self.SizeVariableSpec.Name = sizeSrcName
        self.SizeVariableSpec.Field = self.GetString(opts.Field, "NLMCreateFromPME: 'Field' option passed to AddSizeVariable() is not a string")
        if opts.Coefficient <> null then
            self.SizeVariableSpec.Coefficient = self.GetNumericValue(opts.Coefficient, "NLMCreateFromPME: 'Coefficient' option passed to AddSizeVariable() is not numeric")
        else
            self.SizeVariableSpec.Coefficient = 1.0    
    endItem


    macro "AddShadowPrice"(opts) do
        opts = self.GetOptionsArray(opts, "NLMCreateFromPME: Argument passed to AddShadowPrice() is not an option array")

        // Check if source name is present
        srcName = self.GetString(opts.TargetName, "NLMCreateFromPME: 'TargetName' option passed to AddShadowPrice() is either missing or is not a string")
        srcObj = self.MasterSourcesObject
        chk = srcObj.GetSourceInfo(srcName)
        if chk.Type <> "Table" then
            Throw(ErrMsg + " Source \'" + srcName + "\' is not defined in the master table sources.")
        
        self.ShadowPriceSpec.Name = srcName
        self.ShadowPriceSpec.Field = self.GetString(opts.TargetField, "NLMCreateFromPME: 'TargetField' option passed to AddShadowPrice() is either missing or is not a string")
        
        outTable = self.GetString(opts.OutputShadowPriceTable, "NLMCreateFromPME: 'OutputShadowPriceTable' option passed to AddShadowPrice() is not a string")
        self.CheckOutputFile(outTable, "bin")
        self.ShadowPriceSpec.OutputTable = outTable
        
        if opts.Iterations <> null then
            self.ShadowPriceSpec.Iterations = self.GetNumericValue(opts.Iterations, "NLMCreateFromPME: 'Iterations' option passed to AddShadowPrice() is not numeric")
        else
            self.ShadowPriceSpec.Iterations = self.ShadowIterations
        
        if opts.Tolerance <> null then
            self.ShadowPriceSpec.Tolerance = self.GetNumericValue(opts.Tolerance, "NLMCreateFromPME: 'Tolerance' option passed to AddShadowPrice() is not numeric")
        else
            self.ShadowPriceSpec.Tolerance = self.ShadowTolerance
    endItem


    macro "AddAlternatives"(opts) do
        self.CheckOptionType(opts, "array", "Argument to \'AddAlternatives\' method is not an array")

        altsTable = opts.AlternativesList
        if altsTable <> null then do
            spec = {{"Alternative", "string", 1},
                    {"Utility Column", "string", 0}}
            if altsTable.Constant <> null then
                spec = spec + {{"Constant", "double", 0}}
            self.CheckTable(altsTable, "AlternativesList", spec)
            self.AlternativesTable = CopyArray(altsTable)
        end

        nestSpec = opts.AlternativesTree
        if nestSpec <> null then do
            spec = {{"Parent", "string", 1},
                    {"Alternatives", "string", 1}}
            if nestSpec.ParentNestCoeff <> null then
                spec = spec + {{"ParentNestCoeff", "double", 0}}
            if nestSpec.ParentASC <> null then
                spec = spec + {{"ParentASC", "double", 0}}
            self.CheckTable(nestSpec, "AlternativesTree", spec)
            self.AlternativesTree = CopyArray(nestSpec)
        end
    endItem


    macro "AddUtility"(opts) do
        opts = self.GetOptionsArray(opts, "NLMCreateFromPME: Argument passed to AddUtility() is not an option array")

        // Utility Function
        util = CopyArray(opts.UtilityFunction)
        if util <> null then do
            self.CheckUtilityTable(util)
            self.Utility = util
            if self.ModelType = "Mode Choice" then do
                if self.AlternateUtilFormat = 1 then
                    self.Utility = self.ChangeUtilityFormat(util)
            end
        end

        // Availability Expressions
        availSpec = CopyArray(opts.AvailabilityExpressions)
        if availSpec <> null then do
            self.CheckTable(availSpec, "AvailabilityExpressions", {{"Alternative", "string", 1}, 
                                                                   {"Expression", "string", 1}})
            self.AvailExpressions = availSpec
        end

        // Substitute Strings if provided
        subStrings = opts.SubstituteStrings
        if subStrings <> null then do
            self.CheckSubstituteStrings(subStrings)
            self.SubstituteStrings = subStrings
            self.ReplaceKeys()
        end
    endItem


    /* 
    This could be one of two formats.
    Default: Colums names are 'Expression', 'Description', 'Filter' and columns for each alternative that contain coefficients
    Alternate: Columns names are 'Alternative', 'Expression', 'Segment', 'Coefficient' and 'Description'
    */
    private macro "CheckUtilityTable"(util) do
        self.CheckOptionType(util, "array", "\'UtilityFunction\' is not a table (array)")
        chkArr = {{"expression", "string", 1}}

        if util.Coefficient <> null then do
            self.AlternateUtilFormat = 1       // Flag to indicate the alternate utility format
            if self.ModelType = "Mode Choice" then
                chkArr = chkArr + {{"alternative", "string", 1},
                                    {"coefficient", "double", 1}}
            else
                chkArr = chkArr + {{"coefficient", "double", 1}}     
        end

        count = 0
        for i = 1 to util.length do
            col = Lower(util[i][1])
            if col = "description" or col = "filter" or col = "segment" then
                chkArr = chkArr + {{col, "string", 0}}
            else if col <> "expression" and self.AlternateUtilFormat = 0 then do
                chkArr = chkArr + {{col, "double", 0}}  // Coeff cols where col name is the altenative name
                count = count + 1
            end
        end
        if count = 0 and self.AlternateUtilFormat = 0 then // Better have column(s) with double values for the alternative coeffs if the default format is being used
            Throw("\'UtilityFunction\' is missing columns for alternatives")
        self.CheckTable(util, "UtilityFunction", chkArr)
    endItem


    private macro "ChangeUtilityFormat"(util) do
        nRows = util.Coefficient.Length
        if nRows = 0 then
            Throw("NLMCreateFromPME: No rows in utility table")    
        
        // Change format
        updatedUtil = null
        updateUtil.Expression = CopyArray(util.Expression)
        if util.Description <> null then
            updateUtil.Description = CopyArray(util.Description)
        if util.Filter <> null then
            updateUtil.Filter = CopyArray(util.Filter)
        if util.Segment <> null then
            updateUtil.Segment = CopyArray(util.Segment)
        
        // Generate and fill columns for alternatives
        altArray = util.Alternative
        altArrayL = altArray.Map(do (f) Return(Lower(f)) end)
        alts = SortArray(altArrayL, {Unique: 'True'})
        /*for alt in alts do
            dim x[nRows]
            updateUtil.(alt) = CopyArray(x)
        end*/

        coeffs = util.Coefficient
        for i = 1 to nRows do
            rowAlt = altArrayL[i]    // Alternative in the current row
            for alt in alts do
                if rowAlt = alt then
                    updateUtil.(alt) = updateUtil.(alt) + {coeffs[i]}
                else
                    updateUtil.(alt) = updateUtil.(alt) + {}    
            end
        end
        Return(updateUtil)
    endItem


    private macro "CheckSubstituteStrings"(subs) do
        ErrMsg = "Option \'SubstituteStrings\' needs to be an options array with find and replace string pairs"
        self.CheckOptionType(subs, "array", ErrMsg)
        for i = 1 to subs.length do
            pair = subs[i]
            self.CheckOptionType(pair, "array", ErrMsg)
            if pair.Length <> 2 then
                Throw(ErrMsg)
            self.CheckOptionType(pair[1], "string", ErrMsg)
            self.CheckOptionType(pair[2], "string", ErrMsg)
        end    
    endItem


    // This macro replaces all substitute strings such as {P} for time period in:
    // 1. Utility Spec 'Variable' and 'Filter' columns
    // 2. Availability Expressions
    private macro "ReplaceKeys" do
        // sub_strings = self.SubstituteStrings
        // Now deal with other specifications/inputs
        arrs = {self.Utility.Expression, self.Utility.Filter, self.AvailExpressions.Expression}
        for i = 1 to arrs.length do
            arr = arrs[i]
            if arr <> null then do
                for j = 1 to arr.length do
                    arr[j] = self.FindAndReplace(arr[j])
                end
            end
        end
    enditem


    // Given input string, loop over all find and replace pairs to produce the output_string
    private macro "FindAndReplace"(input_str) do
        sub_strings = self.SubstituteStrings
        output_str = input_str
        for i = 1 to sub_strings.length do
            pair = sub_strings[i]
            find_str = pair[1]
            repl_str = pair[2]
            output_str = Substitute(output_str, find_str, repl_str,)
        end
        Return(output_str)
    enditem


    macro "AddSegmentConstants"(opts) do
        opts = self.GetOptionsArray(opts, "array", "Argument to 'AddSegmentConstants()' is not an options array")

        segConsts = opts.SegmentConstants
        if segConsts = null then
            Throw("NLMCreateFromPME: Invalid option to method SegmentConstants(). Specify 'SegmentConstants' table")
        
        self.CheckTable(segConsts, "SegmentConstants", {{"Alternative", "string", 1}})
        self.SegmentConstants = CopyArray(segConsts)
    endItem


    // Main macro that creates the .mdl/.dcm file and runs the model
    macro "Evaluate" do
        on escape, error, notfound do
            ErrorMsg = GetLastError({"Reference Info": "False"})
            ShowMessage(ErrorMsg)
            Return()
        end

        self.GetModelFileName()                 // Updates value of self.ModelFile (if not specified)
        self.Validate()                         // Perform a few additional run time validations
        self.GetModelSources()                  // Compiles list of sources that are actually used in the model
        self.GetAlternatives()                  // Gets alternatives, ASCs and Thetas from various inputs
        self.CreateModel()                      // Create .mdl or .dcm file
        if self.RunModel then do
            self.ValidateOutputFormat()
            self.Run()                          // Run Model
        end

        ret = self.ModelInfo()                  // Get Key Model Details to return
        self.WriteToReport()                    // Basic reporting of model details/shares
        self.Cleanup()
        
        on escape, error, notfound default
        Return(ret)
    enditem


    private macro "GetModelFileName" do
        type = self.ModelType
        if type = 'Destination Choice' then
            ext = ".dcm"
        else
            ext = ".mdl"
        
        if self.ModelFile = null then
            self.ModelFile = GetRandFileName("*" + ext)
        else do
            pth = SplitPath(self.ModelFile)
            if Lower(pth[4]) <> ext then
                Throw("Specified output model file does not have the correct extension for a " + type + " model")
        end
    enditem


    private macro "Validate" do
        if self.PrimarySpec = null then
            Throw("Please specify the \'PrimarySpec\' property.\nThe primary spec is the source name to which the model is applied.")
        
        if self.DestinationsSource = null and self.AlternativesTree = null and self.Utility = null then
            Throw("Please specify the model alternatives.")
        
        if self.RunModel and self.OutputSpec = null then
            Throw("Please specify the \'OutputSpec\' property.\nThe output spec contains information on the model outputs.")
        
        if self.ModelType = 'Mode Choice' and self.SizeVariableSpec <> null then
            Throw("Method AddSizeVariable() can only be specified for a destination choice model.")

        if self.ShadowPriceSpec <> null then do
            if self.ModelType = 'Mode Choice' or (self.ModelType = 'Destination Choice' and self.isAggregateModel) then
                Throw("Method AddShadowPrice() can only be specified for a disaggregate destination choice model.")     
        end

        if self.ModelType = 'Destination Choice' and self.ReportShares then
            Throw("Shares summary can only be reported for Mode Choice Models. Please set \'ReportShares\' flag to 0.")

        if self.ModelType = 'Destination Choice' then
            self.CheckDestChoiceUtility()

        if self.AlternativesTable then
            self.ValidateAlternativesTable()
        
        if self.TotalsSpec <> null then
            self.ValidateTotalsSpec()

        if self.ModelType = 'Mode Choice' and self.ReportShares and self.isAggregateModel then do
            if self.TotalsSpec = null then
                Throw("Please specify the \'AddTotalsSpec()\' method in order to create summary shares for aggregate mode choice models.")
            if self.OutputSpec.Totals = null then
                Throw("Please specify the Totals matrix in call to \'AddOutputSpec()\' method. This is required in order to create summary shares for aggregate mode choice models.")    
        end

        if self.ModelType = 'Destination Choice' and self.OutputSpec.ProbabilityTable <> null then
            Throw("Option 'ProbabilityTable' in \'AddOutputSpec()\' method not valid for a destination choice model.")    
    enditem


    private macro "CheckDestChoiceUtility" do
        util = self.Utility
        nCols = util.Length - 1     // -1 to account for the 'Expression' column
        if util.Filter <> null then // Accounting for the presence of the optional 'Filter' column
            nCols = nCols - 1
        if util.Description <> null then // Accounting for the presence of the optional 'Description' column
            nCols = nCols - 1
        if util.Segment <> null then // Accounting for the presence of the optional 'Segment' column
            nCols = nCols - 1
        
        if self.ModelType = 'Destination Choice' and nCols > 1 then
            Throw("Incorrect utility format for a destination choice model.\nDestination Choice models can only have one common utility column.")
    enditem


    private macro "ValidateAlternativesTable" do
        util = self.Utility
        altsTable = self.AlternativesTable
        if altsTable <> null then do
            // Now check if the values specified in the "Utility Column" exist as columns in the utility table
            util_cols = altsTable.[Utility Column]
            for col in util_cols do
                if col <> null then do
                    if util.(col) = null then
                        Throw("\'AlternativesList\' has \'" + col + "\' specified in [Utility Column] that is missing in the utility table")
                end
            end
        end
    enditem


    private macro "ValidateTotalsSpec" do
        ProdSpec = self.TotalsSpec
        if ProdSpec <> null and !self.isAggregateModel then
            Throw("\'TotalsSpec\' is not an available option for disaggregate models.")
        else if ProdSpec <> null and self.isAggregateModel then do
            if self.ModelType = "Mode Choice" then do
                if ProdSpec.MatrixCore = null then
                    Throw("\'TotalsSpec.Core\' option missing. Please indicate the matrix core with the totals.")
            end
            else do // Destination Choice
                if ProdSpec.ZonalField = null then
                    Throw("\'TotalsSpec.ZonalField\' option missing. Please indicate the field containing the production vector.")
            end
        end
    endItem


    private macro "ValidateOutputFormat" do
        outSpec = self.OutputSpec
        if outSpec = null then
            Throw("Please call method to AddOutputSpec() before evaluating the model")
        modelType = self.ModelType
        if self.isAggregateModel then do
            // Check for Probability Matrix Input. Has to be included.
            probFile = outSpec.Probability
            if probFile = null then
                Throw("Please specify the output probability matrix \'OutputSpec.Probability\'")
            self.CheckOutputFile(probFile, "mtx")
            // Other Optionals
            totalsFile = outSpec.Totals
            if totalsFile <> null then do
                if self.TotalsSpec = null then do
                    if modelType = 'Mode Choice' then
                        Throw("Please specify \'TotalsSpec\' that contains source name and Core for the PA matrix")
                    else
                        Throw("Please specify \'TotalsSpec\' that contains source name and Field for the input productions")
                end
            end    
        end
        else do // Disaggregate Model
            outFld = outSpec.ChoicesField            
            if outFld <> null then do
                outSrc = self.PrimarySpec.Name
                outvw = self.ModelTableSources.(outSrc).View
                tmp = self.CheckFieldValidity(outvw, outFld)
                tmpSpec = GetFieldFullSpec(outvw, tmp)
                
                // Set output field type
                if modelType = 'Destination Choice' then do
                    if GetFieldType(tmpSpec) <> "Integer" then
                        Throw("\'ChoicesField\' has to be of type Integer for destination choice.")
                end    
                else do // Mode Choice
                    if GetFieldType(tmpSpec) <> "Integer" and GetFieldType(tmpSpec) <> "String" then
                        Throw("\'ChoicesField\' has to be of type Integer or String.")
                end
                self.OutputSpec.ChoicesFieldType = GetFieldType(tmpSpec)
            end
            if self.ModelType = 'Mode Choice' and self.OutputSpec.ProbabilityTable = null then
                self.OutputSpec.ProbabilityTable = GetRandFileName("ProbMC*.bin")
            
            // Note: The choices file is always created.
            // If the user has specified a choice field, then the values are finally copied over.
            if self.ModelType = 'Mode Choice' and self.OutputSpec.ChoicesTable = null then
                self.OutputSpec.ChoicesTable = GetRandFileName("ChoicesMC*.bin")    
        end
    endItem


    // Identify potential model sources from
    // 1. Utility 'Expression' and 'Filter'
    // 2. Primary Spec
    // 3. Destinations source (if present)
    // 4. Alternative Availability Expressions (if present)
    // 5. Totals Spec
    // 6. Size Variable Source
    // 7. Shadow Price Source
    // Populates self.ModelMatrixSources and self.ModelTableSources
    private macro "GetModelSources" do
        // 1. Utility
        util = self.Utility
        ErrMsg = "Utility specification has invalid expression or refers to undefined source."
        self.GetSources(util.Expression, ErrMsg)
        self.GetSources(util.Filter, ErrMsg)

        // 2. Primary Spec
        ErrMsg = "Primary specification has undefined source."
        self.GetSource(self.PrimarySpec.Name, ErrMsg)

        // 3. Alternate availabilities
        availExprs = self.AvailExpressions
        if availExprs <> null then do
            ErrMsg = "Availability expressions are invalid or refer to undefined source."
            self.GetSources(availExprs.Expression, ErrMsg)
        end

        // 4. Destinations Source
        destSrc = self.DestinationsSource
        if destSrc <> null then do
            ErrMsg = "Destination source is undefined."
            self.GetSource(destSrc, ErrMsg)
        end

        // 5. Totals Spec
        totalsSpec = self.TotalsSpec
        if totalsSpec <> null then do
            ErrMsg = "Source in TotalsSpec.Name is undefined."
            self.GetSource(totalsSpec.Name, ErrMsg)
        end

        // 6. Size Variable Source
        sizeVarSpec = self.SizeVariableSpec
        if sizeVarSpec <> null then do
            ErrMsg = "Source in SizeVariableSpec.Name is undefined."
            self.GetSource(sizeVarSpec.Name, ErrMsg)  
        end

        // 7. Shadow Price Source
        shadowSpec = self.ShadowPriceSpec
        if shadowSpec <> null then do
            ErrMsg = "Source in ShadowPriceSpec.Name is undefined."
            self.GetSource(shadowSpec.Name, ErrMsg)  
        end
    endItem


    private macro "GetSources"(arr, ErrMsg) do
        for expr in arr do
            expr = Trim(expr)
            if expr <> null and lower(expr) <> 'constant' then do
                parts = ParseNLMExpression(expr)
                if parts = null then
                    Throw(ErrMsg)
                
                for part in parts do
                    strs = ParseString(part, ".")
                    if strs.length = 1 then
                        Throw(ErrMsg)
                    srcName = strs[1]
                    fldName = strs[2]
                    tmp = ParseString(srcName, "[]") // Remove leading and trailing brackets
                    srcName = tmp[1]
                    self.GetSource(srcName, ErrMsg)
                end
            end
        end        
    endItem


    private macro "GetSource"(srcName, ErrMsg) do
        srcObj = self.MasterSourcesObject
        
        chk = srcObj.CheckSource(srcName)
        if !chk then
            Throw(ErrMsg + " Source \'" + srcName + "\' undefined.")
                
        srcInfo = srcObj.GetSourceInfo(srcName)
        srcName = srcInfo.Name // Use updated name as defined in the master sources table for consistency

        // Add sources to list only if not already present
        if self.ModelTableSources.(srcName) = null and self.ModelMatrixSources.(srcName) = null then do
            if !srcInfo.JoinedView then do
                file = srcInfo.File
                if !GetFileInfo(file) then
                    Throw("File \'" + file + "\' used in the choice model specification not found.")
            end
                    
            if srcInfo.Type = "Table" then
                self.ModelTableSources.(srcName) =  CopyArray(srcInfo)
            else
                self.ModelMatrixSources.(srcName) =  CopyArray(srcInfo)
        end
    endItem


    private macro "GetAlternatives" do
        if self.ModelType = "Destination Choice" then
            self.GetDestinations()
        else do // Mode Choice Model
            if self.AlternativesTree <> null or self.AlternativesTable <> null then do
                if self.AlternativesTree <> null then
                    self.ProcessAlternativesTree()
                if self.AlternativesTable <> null then
                    self.ProcessAlternativesList()    
            end
            else
                self.GetAlternativesFromUtility()
        end

        if self.SegmentConstants <> null then
            self.ProcessSegmentConstants()
    endItem


    private macro "GetDestinations" do
        srcObj = self.MasterSourcesObject
        m = srcObj.OpenSource(self.DestinationsSource)
        dests = GetMatrixIndexIds(m, self.DestinationsIndex)
        self.Alternatives.Root = dests.Map(do (f) Return(String(f)) end)
        self.LeafAlts = self.Alternatives.Root
        m = null
    endItem


    private macro "ProcessAlternativesTree" do
        nests = self.AlternativesTree
        parents = nests.Parent
        alts = nests.Alternatives
        ascs = nests.ParentASC
        thetas = nests.ParentNestCoeff
        rootPos = ArrayPosition(parents, {"Root"},)
        if rootPos = 0 then
            Throw("Root alternative not found in \'Parent\' column in \'Spec.AlternativesTree\'")
        for i = 1 to parents.length do
            parent = Trim(parents[i])
            childAlts = ParseString(alts[i], ",")
            childAlts = childAlts.Map(do (f) Return(Trim(f)) end)
            self.Alternatives.(parent) = CopyArray(childAlts)
            if ascs <> null then
                self.ASCs.(parent) = ascs[i]
            if thetas <> null then
                self.Thetas.(parent) = thetas[i]
        end
    endItem


    private macro "ProcessAlternativesList" do
        altsTable = self.AlternativesTable
        names = altsTable.Alternative
        names = names.Map(do (f) Return(Trim(f)) end)
        
        if self.AlternativesTree = null then // otherwise the input tree structure has already defined the alternatives
            self.Alternatives.Root = names
        
        ascs = altsTable.Constant
        if ascs <> null then do
            for i = 1 to ascs.length do
                if ascs[i] <> null then
                    self.ASCs.(names[i]) = nz(self.ASCs.(names[i])) + ascs[i]
            end
        end
    endItem


    private macro "GetAlternativesFromUtility" do
        util = self.Utility
        for i = 1 to util.length do
            col = util[i][1] // The column name
            if Lower(col) <> "expression" and Lower(col) <> "filter" and Lower(col) <> "description" and Lower(col) <> "segment" then
                self.Alternatives.Root =  self.Alternatives.Root + {col}
        end
        
        if self.Alteratives.Root.Length = 1 then do // Binary choice. Add extra alternative.
            altName = self.Alteratives.Root[1]
            self.Alternatives.Root = self.Alternatives.Root + {"Not_" + altName}
        end    
    endItem


    macro "ProcessSegmentConstants" do
        segConsts = self.SegmentConstants
        seg = self.Segment
        if seg = null then
            Throw("NLMCreateFromPME: Please specify segment attribute required to apply the appropriate input segment constants")
        if segConsts <> null then do
            alts = segConsts.Alternative
            ascs = segConsts.(seg)
            for i = 1 to alts.length do
                asc = ascs[i]
                if asc <> null then do
                    asc = self.GetNumericValue(asc, "NLMCreateFromPME: Segment constant in table not numeric")
                    self.ASCs.(alts[i]) = nz(self.ASCs.(alts[i])) + asc
                end
            end
        end 
    endItem


    // Create mdl or dcm file
    macro "CreateModel" do
        self.CreateShell()
        self.SetSources()
        self.SetAlternatives()
        self.SetAvailabilities()
        self.SetUtility()
        self.SetTotalsSpec()
        self.SetShadowPrice()
        self.SetSurveyArrays() // For special "Survey Array" sources to allow person by zone matrices.
        self.WriteModelToFile()
    endItem


    private macro "CreateShell" do
        self.Model = CreateObject("NLM.Model")
        self.Model.Clear()
        self.Model.ToLineRecord()
        seg = self.Model.CreateSegment("*", , ) 
    endItem


    private macro "SetSources" do
        self.SetTableSources()
        self.SetMatrixSources()
    endItem


    private macro "SetTableSources" do
        srcObj = self.MasterSourcesObject
        model = self.Model
        // Loop over model table sources, open the files and add them
        for item in self.ModelTableSources do
            src = item[2]
            srcName = src.Name
            vw = srcObj.OpenSource(srcName)
            
            spec = null
            spec.IDField = src.IDField
            spec.View = vw
            
            isPrimary = 0
            srcType = "Zonal"
            if Lower(srcName) = Lower(self.PrimarySpec.Name) then do
                isPrimary = 1
                srcType = "Survey"
                if self.PrimarySpec.Filter <> null then do
                    spec.Set = "___Selection"
                    SetView(vw)
                    qry = "Select * where " + self.PrimarySpec.Filter
                    n = SelectByQuery(spec.Set, "several", qry,)
                    if n = 0 then
                        Throw("No selected records in Primary View")
                    self.ModelTableSources.(srcName).Filter = self.PrimarySpec.Filter
                    self.PrimarySpec.Set = spec.Set
                    if self.PrimarySpec.OField <> null then
                        spec.OField = self.PrimarySpec.OField
                    if self.PrimarySpec.DField <> null then
                        spec.DField = self.PrimarySpec.DField
                end
                if self.ModelMatrixSources <> null then do
                    {flds, specs} = GetFields(vw,)
                    if self.PrimarySpec.OField = null then
                        Throw("Please specify the Origin field for the primary view specification.")
                    else do
                        if ArrayPosition(flds, {self.PrimarySpec.OField},) = 0 then
                            Throw("The Origin field \'" + self.PrimarySpec.OField + "\' in the primary view specification not found.")    
                    end
                    
                    if self.ModelType = "Mode Choice" then do
                        if self.PrimarySpec.DField = null then
                            Throw("Please specify the Destination field for the primary view specification.")
                        else do
                            if ArrayPosition(flds, {self.PrimarySpec.DField},) = 0 then
                                Throw("The Destination field \'" + self.PrimarySpec.DField + "\' in the primary view specification not found.")    
                        end   
                    end
                    
                    spec.OField = self.PrimarySpec.OField
                    spec.DField = self.PrimarySpec.DField // Can be null for Dest Choice
                end
            end
            self.ModelTableSources.(srcName).View = vw // Keep track of the opened view for the source
            model.CreateDataSource(isPrimary, srcType, src.Name, spec,)
        end
    endItem


    private macro "SetMatrixSources" do
        srcObj = self.MasterSourcesObject
        model = self.Model
        // Loop over model matrix sources, open the files and add them
        for item in self.ModelMatrixSources do
            src = item[2]
            srcName = src.Name
            m = srcObj.OpenSource(src.Name)
            spec = null
            spec.RowIdx = src.RowIndex
            spec.ColIdx = src.ColIndex
            spec.FileName = src.File
            spec.FileLabel = GetMatrixName(m)
            if Lower(src.Name) = Lower(self.PrimarySpec.Name) then
                isPrimary = 1
            else
                isPrimary = 0
            self.ModelMatrixSources.(srcName).Handle = m //Keep track of the matrix handle for this source
            model.CreateDataSource(isPrimary, "Matrix", src.Name, spec, )
        end
    endItem


    private macro "SetAlternatives" do
        if self.ModelType = 'Destination Choice' then
            self.SetDestChoiceAlternatives()
        else
            self.SetModeChoiceAlternatives()
    endItem


    private macro "SetDestChoiceAlternatives" do
        // Add Destination Common Altenative
        model = self.Model
        seg = model.GetSegment("*")
        modelAlt = seg.CreateAlternative("Destinations", "ROOT",,)
        // Set the matrix index spec that defines the destinations
        modelAlt.DestSrc = self.DestinationsSource
        modelAlt.DestIdx = self.DestinationsIndex
    endItem

    
    // Process the main list of alteratives and add them to the model
    private macro "SetModeChoiceAlternatives" do
        self.LeafAlts = null
        alts = self.Alternatives
        masterList = {"Root"}
        while masterList <> null do
            // Add current entries from masterList
            newList = null
            for parent in masterList do
                self.AddChildren(parent)
                if alts.(parent) = null then
                    self.LeafAlts = self.LeafAlts + {parent}
                else
                    newList = newList + alts.(parent)
            end
            masterList = CopyArray(newList)
        end    
    endItem


    // Adds sub-alternatives immediately below the parent
    // Assigns the ASC and Theta values to these sub-alternatives
    private macro "AddChildren"(parent) do
        model = self.Model
        seg = model.GetSegment("*")
        altsArr = self.Alternatives.(parent)
        for alt in altsArr do
            altName = Trim(alt)
            modelAlt = seg.CreateAlternative(altName, parent,,)
            modelAlt.ASC.Coeff = self.ASCs.(altName)
            if self.Alternatives.(alt) <> null then // Not leaf Alt
                seg.CreateThetaTerm(modelAlt, self.Thetas.(altName))
        end
    endItem


    private macro "SetAvailabilities" do
        availSpecs = self.AvailExpressions
        if availSpecs = null then
            Return()
        
        model = self.Model
        seg = model.GetSegment("*")
        availAlts = availSpecs.Alternative
        availExprs = availSpecs.Expression
        for i = 1 to availAlts.length do
            altName = availAlts[i]
            expr = Trim(availExprs[i])
            self.ValidateExpression(expr)
            exprName = self.CreateExpressionSource(expr, "Avail" + altName)
            da = model.CreateDataAccess("data", exprName,)
            alt = seg.GetAlternative(altName)
            alt.SetAvail(da)
        end
    endItem


    private macro "SetUtility" do
        if self.ModelType = 'Destination Choice' then
            self.SetDestChoiceUtility()
        else
            self.SetModeChoiceUtility()
    endItem


    private macro "SetDestChoiceUtility" do
        utility = self.Utility
        if utility <> null then do
            for i = 1 to utility.length do
                col = utility[i][1] // Name of col
                if Lower(col) <> "filter" and Lower(col) <> "description" and Lower(col) <> "expression" and Lower(col) <> "segment" then
                    coeffCol = col
            end
            coeffs = utility.(coeffCol)
            if coeffs <> null then
                self.SetAlternativeUtility("Destinations", coeffs)
        end

        if self.SizeVariableSpec <> null then
            self.SetSizeVariable("Destinations")
    endItem


    private macro "SetModeChoiceUtility" do
        altsTable = self.AlternativesTable
        utility = self.Utility
        if utility <> null then do
            if altsTable <> null then do // The table contains the alterative names and the corresponding name of the coeff column in the utility spec
                alts = altsTable.Alternative
                cols = altsTable.[Utility Column]
                for i = 1 to alts.length do
                    altName = alts[i]
                    colName = cols[i]
                    if colName <> null then do
                        coeffs = utility.(colName)
                        self.SetAlternativeUtility(altName, coeffs)
                    end
                end
            end
            else do // The column names with coeff values in the utility table are also the alternative names
                for i = 1 to utility.length do
                    col = utility[i][1] // Name of col
                    if Lower(col) <> "filter" and Lower(col) <> "description" and Lower(col) <> "expression" and Lower(col) <> "segment" then
                        self.SetAlternativeUtility(col, utility.(col)) // (Alternative Name, coeffs)
                end
            end
        end
    endItem


    private macro "SetAlternativeUtility"(altName, coeffs) do
        expressions = self.Utility.Expression
        filters = self.Utility.Filter
        segments = self.Utility.Segment
        C = 0
        for i = 1 to coeffs.length do
            C = C + 1
            coeff = coeffs[i]
            if coeff = null or coeff = 0 then
                goto nextCoeff
            
            if segments <> null then do
                seg = Lower(segments[i])
                if seg <> null and seg <> self.Segment then
                    goto nextCoeff
            end
            
            expr = Trim(expressions[i])
            if Lower(expr) = "constant" then do
                self.UpdateASC(altName, coeff)
                goto nextCoeff
            end
            
            if filters <> null then do
                filter = Trim(filters[i])
                if filter <> null then
                    expr = "(" + expr + ")*(" + filter + ")"
            end

            exprOut = self.ValidateExpression(expr)
            exprName = self.CreateExpressionSource(exprOut,)
            varName = "B" + String(C) + "_" + altName + "_" + exprName
            
            // Add expression term to utility
            self.AddUtilityItem(altName, varName, exprName, coeff)
         nextCoeff:
        end
    endItem


    private macro "SetSizeVariable"(altName) do
        srcName = self.SizeVariableSpec.Name
        fldName = self.SizeVariableSpec.Field
        coeff = self.SizeVariableSpec.Coefficient

        // Check if field exists in table
        vw = self.ModelTableSources.(srcName).View
        outFld = self.CheckFieldValidity(vw, fldName)
        fldspec = GetFieldFullSpec(vw, outFld) + ".D"

        // The expression is the log of the size variable
        expr = "if " + fldspec + " > 0 then Log(" + fldspec + ") else null"
        exprOut = self.ValidateExpression(expr)
        exprName = self.CreateExpressionSource(exprOut,)
        varName = "B" + "_Size_" + exprName

        // Add expression term to utility
        self.AddUtilityItem(altName, varName, exprName, coeff)
    endItem


    private macro "AddUtilityItem"(altName, varName, exprName, coeff) do
        model = self.Model
        seg = model.GetSegment("*")
        alt = seg.GetAlternative(altName)
        if alt = null then
            Throw("NLMCreateFromPME: Alternative '" + altName + "' not found. Please check specification for errors.")

        fld = model.CreateField(varName,)
        term = seg.CreateTerm(fld.Name, coeff,)
        da = model.CreateDataAccess("data", exprName,)
        alt.SetAccess(fld, da,)  
    endItem


    private macro "UpdateASC"(altName, coeff) do
        model = self.Model
        seg = model.GetSegment("*")
        alt = seg.GetAlternative(altName)
        alt.ASC.Coeff = nz(alt.ASC.Coeff) + coeff  
    endItem


    private macro "ValidateExpression"(expr) do
        ErrMsg = "Expression \'" + expr + "\' invalid.\n"
        parts = ParseNLMExpression(expr)
        for part in parts do
            {srcName, varName, suffix} = ParseString(part, ".")
            tmp = ParseString(srcName, "[]") // Remove leading and trailing brackets
            srcName = tmp[1]
            if self.ModelTableSources.(srcName) <> null then do
                srcNameUpd = self.ModelTableSources.(srcName).Name // Returns the name as specified in the model sources object
                vw = self.ModelTableSources.(srcName).View
                {flds, specs} = GetFields(vw,)
                if ArrayPosition(flds, {varName},) = 0 then do
                    ErrMsg = ErrMsg + "Field \'" + varName + "\' not found in source \'" + srcName + "\'"
                    Throw(ErrMsg)
                end
                if self.ModelType = "Destination Choice" and Lower(srcName) <> Lower(self.PrimarySpec.Name) and Lower(suffix) <> 'd' then do
                    ErrMsg = ErrMsg + "Incorrect zonal table affiliation for a destination choice model.\n"
                    ErrMsg = ErrMsg + "Expressions on zonal table sources should contain .D for a destination attribute.\n"
                    Throw(ErrMsg)
                end
                if Lower(srcName) <> Lower(self.PrimarySpec.Name) and Lower(suffix) <> 'o' and Lower(suffix) <> 'd' then do
                    ErrMsg = ErrMsg + "Expressions on zonal table sources should contain the access type affiliation.\n"
                    ErrMsg = ErrMsg + "Please specify a suffix of .O for an origin attribute or a .D for a destination attribute"
                    Throw(ErrMsg)
                end
                if Lower(srcName) = Lower(self.PrimarySpec.Name) and suffix <> null then do
                    ErrMsg = ErrMsg + "Expressions on the primary source cannot contain origin or destination affiliations.\n"
                    Throw(ErrMsg)
                end
            end
            else if self.ModelMatrixSources.(srcName) <> null then do
                srcNameUpd = self.ModelMatrixSources.(srcName).Name // Returns the name as specified in the model sources object
                m = self.ModelMatrixSources.(srcName).Handle
                cores = GetMatrixCoreNames(m)
                tmp = ParseString(varName, "[]") // Remove leading and trailing brackets
                coreName = tmp[1] 
                if ArrayPosition(cores, {coreName},) = 0 then do
                    ErrMsg = ErrMsg + "Matrix core \'" + varName + "\' not found in source \'" + srcName + "\'"
                    Throw(ErrMsg)
                end
            end
            else do
                ErrMsg = ErrMsg + "Source \'" + srcName + "\' not found in the model file/specification"
                Throw(ErrMsg)
            end
            expr = Substitute(expr, srcName, srcNameUpd,) // Make all source names consistent with the model sources object
        end
        Return(expr)
    endItem


    private macro "CreateExpressionSource"(expr, descr) do
        model = self.Model
        exprs = self.ModelExpressions.Expressions
        exprNames = self.ModelExpressions.Names
        pos = ArrayPosition(exprs, {expr},)
        if pos = 0 then do // New Expression
            spec = null
            spec.Expression = expr    
            n = exprs.Length
            exprName = "Expr" + String(n+1) + descr
            model.CreateDataSource(0, "Expression", exprName, spec,)
            self.ModelExpressions.Expressions = self.ModelExpressions.Expressions + {expr}    
            self.ModelExpressions.Names = self.ModelExpressions.Names + {exprName}    
        end
        else // Reuse
            exprName = exprNames[pos]
        Return(exprName)
    endItem


    private macro "SetTotalsSpec" do
        totalsSpec = self.TotalsSpec
        if self.isAggregateModel and totalsSpec <> null then do
            model = self.Model
            seg = model.GetSegment("*")
            totalsSrc = totalsSpec.Name
            if self.ModelType = "Mode Choice" then do
                m = self.ModelMatrixSources.(totalsSrc).Handle
                cores = GetMatrixCoreNames(m)
                core = totalsSpec.MatrixCore
                if ArrayPosition(cores, {core},) = 0 then
                    Throw("Matrix Core \'" + core + "\' not found in totals matrix source \'" + totalsSrc + "\'")
                da = model.CreateDataAccess("data", totalsSrc, core)
            end
            else do
                vw = self.ModelTableSources.(totalsSrc).View
                fld = totalsSpec.ZonalField
                outFld = self.CheckFieldValidity(vw, fld)
                da = model.CreateDataAccess("data", totalsSrc, outFld,)
            end
            seg.SetTotals(da)
        end
    endItem


    private macro "SetShadowPrice" do
        if self.ShadowPriceSpec <> null then do
            srcName = self.ShadowPriceSpec.Name
            fldName = self.ShadowPriceSpec.Field

            // Check if field exists in table
            vw = self.ModelTableSources.(srcName).View
            outFld = self.CheckFieldValidity(vw, fldName)

            // Set attractions variable within the model
            model = self.Model
            seg = model.GetSegment("*")
            da = model.CreateDataAccess("data", srcName, fldName)
            seg.SetAttractions(da)    
        end
    endItem


    private macro "SetSurveyArrays" do
        model = self.Model
        for item in self.ModelMatrixSources do
            src = item[2]
            personBased = src.PersonBased
            if personBased = 1 then do
                modelSrc = model.GetDataSource(src.Name)
                modelSrc.Type = "Survey Array"
            end
        end
    endItem


    private macro "WriteModelToFile" do
        model = self.Model
        modelFile = self.ModelFile
        model.Write(modelFile)
        model.Clear()
        model = null
    endItem


    // Note all files are open before this is run
    macro "Run" do
        if GetViews() = null and GetMatrices() = null then
            Throw("Required files to run mode or destination choice not open")
        
        if self.ModelType = 'Mode Choice' then
            self.RunModeChoice()
        else
            self.RunDestinationChoice()            
    endItem


    macro "RunModeChoice" do
        outSpec = self.OutputSpec
        
        o = CreateObject("Choice.Mode")
        o.ModelFile = self.ModelFile
        o.RandomSeed = self.RandomSeed
        if self.isAggregateModel then do
            o.AddMatrixOutput("*", {Probability: outSpec.Probability})
            if outSpec.Utility <> null then
                o.AddMatrixOutput("*", {Utility: outSpec.Utility})
            if outSpec.Logsum <> null then
                o.AddMatrixOutput("*", {Logsum: outSpec.Logsum})
            if outSpec.Totals <> null then
                o.AddMatrixOutput("*", {Totals: outSpec.Totals})
        end
        else do // Disaggregate. Always write out the probability and choices table.
            o.OutputProbabilityFile = outSpec.ProbabilityTable
            o.OutputChoiceFile = outSpec.ChoicesTable
        end

        // Run Model
        o.Run()

        // If choices field provided, copy over values from choice table
        if !self.isAggregateModel then
            vwChoices = self.OpenChoicesTable() // An In-Memory view of the output choices table
        
        if outSpec.ChoicesField <> null then
            self.CopyChoicesField(vwChoices)

        if self.ReportShares then
            self.CreateSummaryShares(vwChoices)

        if !self.isAggregateModel then
            CloseView(vwChoices)
    endItem


    macro "RunDestinationChoice" do
        outSpec = self.OutputSpec
        
        o = CreateObject("Choice.Destination")
        o.ModelFile = self.ModelFile
        o.RandomSeed = self.RandomSeed
        if self.isAggregateModel then do
            o.ProbabilityMatrix({MatrixFile: outSpec.Probability, MatrixLabel: "DC Probabilities"})
            if outSpec.Totals <> null then
                o.TotalsMatrix({MatrixFile: outSpec.Totals, MatrixLabel: "DC Totals"})
            if outSpec.Utility <> null then
                o.UtilityMatrix(outSpec.Utility)    
        end
        else do
            if outSpec.ChoicesTable <> null then
                o.OutputFile = outSpec.ChoicesTable
            else do
                src = self.PrimarySpec.Name
                fld = outSpec.ChoicesField
                vw = self.ModelTableSources.(src).View
                o.OutputField({ViewName: vw, FieldName: fld})
            end

            if self.ShadowPriceSpec <> null then
                o.ShadowPricing({ShadowTable: self.ShadowPriceSpec.OutputTable, /*Iterations: self.ShadowPriceSpec.Iterations,*/ Tolerance: self.ShadowPriceSpec.Tolerance})
        end

        // Run Dest Choice
        o.Run()
    endItem


    private macro "OpenChoicesTable" do
        outFile = self.OutputSpec.ChoicesTable
        objT = CreateObject("AddTables", {TableName: outFile})
        vw = objT.TableView
        vwChoices = ExportView(vw + "|", "MEM", "Choices",,)
        objT = null
        Return(vwChoices)
    endItem


    private macro "CopyChoicesField"(vwC) do
        outSpec = self.OutputSpec
        choicesField = outSpec.ChoicesField

        // Choices Spec
        {fldsC, specsC} = GetFields(vwC,)
        choiceSpec = specsC[1]
        
        // Primary Spec
        src = self.PrimarySpec.Name
        vwP = self.ModelTableSources.(src).View
        ID = self.ModelTableSources.(src).IDField
        primarySpec = GetFieldFullSpec(vwP, ID)
        {fldsP, specsP} = GetFields(vwP,)

        // Determine whether to fill 'Choice' (Alternative Names) or 'ChoiceCode' (Alternative IDs)
        if outSpec.ChoicesFieldType = "String" then
            inputChoiceFld = "Choice"
        else
            inputChoiceFld = "ChoiceCode"    
        
        if ArrayPosition(fldsP, {inputChoiceFld},) > 0 then             // Then the input field is ambiguous
            inputChoiceFld = GetFieldFullSpec(vwC, inputChoiceFld)
        
        if Lower(choicesField) = "choice" or Lower(choicesField) = "choicecode" then  // Then the output field is ambiguous
            choicesField = GetFieldFullSpec(vwP, choicesField)

        vwJ = JoinViews("ChoicesPrimary", choiceSpec, primarySpec,)
        v = GetDataVector(vwJ + "|", inputChoiceFld,)
        SetDataVector(vwJ + "|", choicesField, v, )
        CloseView(vwJ)
    endItem


    private macro "CreateSummaryShares"(vw) do
        alts = self.LeafAlts // Order of LeafAlts and idFld values are consistent
        dim shares[alts.length]
        if self.isAggregateModel then do
            // Get totals matrix to determine shares
            mat = self.OutputSpec.Totals
            m = OpenMatrix(mat,)
            cores = GetMatrixCoreNames(m)
            stats = MatrixStatistics(m,)
            tsum = 0
            for i = 1 to stats.length do
                tsum = tsum + nz(stats.(cores[i]).Sum)
            end

            for i = 1 to alts.length do
                shares[i] = Round((100 * stats.(alts[i]).Sum)/tsum, 2)
            end
            m = null
        end
        else do
            choiceFld = "Choice"                        // Hardcoded in NLM engine
            // Aggregate appropriate table using the choice field
            expr = CreateExpression(vw, "One", "1",)
            vwAgg = AggregateTable("Aggr", vw + "|", "MEM", "Aggr", choiceFld, {{"One", "Count",}},)
            {flds, specs} = GetFields(vwAgg,)
            {vAlt, vCount} = GetDataVectors(vwAgg + "|", {flds[1], flds[2]},)
            sumTotal = VectorStatistic(vCount, "Sum",)
            for i = 1 to alts.length do
                pos = ArrayPosition(v2a(vAlt), {alts[i]},)
                if pos > 0 then
                    shares[i] = Round((100 * vCount[pos])/sumTotal, 2)
            end
            CloseView(vwAgg)
        end
        self.ModelShares = CopyArray(shares)
    endItem


    private macro "WriteToReport" do
        AppendToReportFile(0, self.ModelName + " Model Summary", {{"Section", "True"}})
        AppendTableToReportFile({{Name: "Item", "Percentage Width": 20, Alignment: "Left"},   
                                 {Name: "Value", "Percentage Width": 80, Alignment: "Left"}},
                                {Title: "Model Details", Indent: 2})
        AppendRowToReportFile({"Model Name:", self.ModelName},)
        AppendRowToReportFile({"Model Type:", self.ModelType},)
        AppendRowToReportFile({"Is Aggregate?:", self.isAggregateModel},)
        AppendRowToReportFile({"Model File:", self.ModelFile},)
        AppendRowToReportFile({"Apply Model To:", self.PrimarySpec.Name},)
        if !self.isAggregateModel then do
            if self.PrimarySpec.Filter <> null then
                AppendRowToReportFile({"Selection Set:", self.PrimarySpec.Filter},)
            else
                AppendRowToReportFile({"Selection Set:", "All Records"},) 
        end    

        // Model Alternatives and Model Shares if present
        if self.ModelType = 'Mode Choice' then do
            if self.RunModel and self.ReportShares then do
                AppendTableToReportFile({{Name: "Alternative ID", "Percentage Width": 20, Alignment: "Left"},   
                                         {Name: "Alternative", "Percentage Width": 50, Alignment: "Left"},
                                         {Name: "Share", "Percentage Width": 30, Alignment: "Left"}},
                                        {Title: "Model Alternatives and Shares", Indent: 2})
                for i = 1 to self.LeafAlts.Length do
                    AppendRowToReportFile({i, self.LeafAlts[i], String(self.ModelShares[i])},)    
                end
            end
            else do
                AppendTableToReportFile({{Name: "Alternative ID", "Percentage Width": 20, Alignment: "Left"},   
                                         {Name: "Alternative", "Percentage Width": 80, Alignment: "Left"}},
                                        {Title: "Model Alternatives", Indent: 2})
                for i = 1 to self.LeafAlts.Length do
                    AppendRowToReportFile({i, self.LeafAlts[i]},)    
                end    
            end
        end
        CloseReportFileSection()
    endItem


    private macro "ModelInfo" do
        leafAlts = self.LeafAlts

        ret = null
        ret.ModelName = self.ModelName
        ret.ModelType = self.ModelType
        ret.ModelFile = self.ModelFile
        ret.RunModel = self.RunModel
        ret.Alternatives = self.LeafAlts
        ret.isAggregateModel = self.isAggregateModel
        
        // Table Source Info
        ret.TableSources = null
        for src in self.ModelTableSources do
            currSrc = src[2]
            ret.TableSources = ret.TableSources + {{Label: currSrc.Name, FileName: currSrc.File, ViewName: currSrc.View, Filter: currSrc.Filter}}
        end
        
        // Matrix Source Info
        ret.MatrixSources = null
        for src in self.ModelMatrixSources do
            currSrc = src[2]
            matName = GetMatrixName(currSrc.Handle)
            ret.MatrixSources = ret.MatrixSources + {{Label: matName, FileName: currSrc.File}}
        end

        // Get Alterative ID descriptions
        descStr = null
        for i = 1 to leafAlts.length do
            descStr = descStr + "|" + String(i) + ": " + leafAlts[i]
        end
        ret.AlternativesLookup = descStr

        if self.ReportShares and self.RunModel then
            ret.ModelShares = self.ModelShares
        
        Return(ret)
    endItem


    macro "Cleanup" do
        if self.Model <> null then do
            self.Model.Clear()
            self.Model = null
        end
        
        if self.CloseFiles then do
            for src in self.ModelTableSources do
                currSrc = src[2]
                CloseView(currSrc.View)
            end
            
            for src in self.ModelMatrixSources do
                currSrc = src[2]
                currSrc.Handle = null
            end

            self.ModelTableSources = null
            self.ModelMatrixSources = null
        end

        self.Alternatives = null
        self.LeafAlts = null
        self.ASCs = null
        self.Thetas = null
        self.ModelExpressions = null
        self.ModelShares = null
        
        //if self.ChoicesTable.InMemView <> null then
            //CloseView(self.ChoicesTable.InMemView)
    endItem


    private macro "CheckTable"(option, option_name, colSpec) do
        for i = 1 to colSpec.length do
            colName = colSpec[i][1]
            type = colSpec[i][2]
            isReq = colSpec[i][3]
            column = option.(colName)
            
            ErrMsg = "\'" + option_name + "\'' table is missing column \'" + colName + "\' OR \n\'" + option_name + "." + colName + "\' option is missing"
            if column = null then
                Throw(ErrMsg)
            
            ErrMsg = "\'" + option_name + "." + colName + "\' is not an array"
            self.CheckOptionType(column, "array", ErrMsg)
            
            ErrMsg = "\'" + option_name + "." + colName + "\' is not of type \'" + type + "\'"
            for val in column do
                if val = null and isReq then
                    Throw("Missing value in column " + "\'" + option_name + "." + colName + "\'")
                if val <> null then do // All non-string fields can have nulls
                    if type = "double" and TypeOf(val) = "int" then
                        val = i2r(val)
                    if TypeOf(val) <> type then
                        Throw(ErrMsg)
                end
            end 
        end
    endItem    
endClass


// Class that manages sources for running choice models from PME
Class "Choice Model Sources"(Args, Opts) inherits: "TransCAD.Task"

    init do
        self.MatrixSources = Opts.MatrixSources
        self.TableSources = Opts.TableSources
        self.SourceKeys = Opts.SourceKeys 
        self.Joins = Opts.Joins
        
        if Opts <> null then do
            if Args = null then
                Throw("Please provide the Args for instantiating the \'Choice Model Sources\' class")

            self.CheckInputs()
            self.AddPersonBasedFlags()      // If not already present, update matrix sources to include person based column
            self.ExpandSources()
            self.GetSourceFileNames(Args)
        end
    endItem
 

    macro "CheckInputs" do
        if self.TableSources = null and self.MatrixSources = null then
            Throw("There are no table or matrix sources defined in the flowchart Arguments")

        // 1. Check Table Sources
        tblSrcs = self.TableSources
        if tblSrcs <> null then
            self.CheckTable(tblSrcs, "TableSources", {{"Name", "string", 1},
                                                      {"IDField", "string", 1}})
        // 2. Check Matrix Sources
        mtxSrcs = self.MatrixSources
        if mtxSrcs <> null then
            self.CheckTable(mtxSrcs, "MatrixSources", {{"Name", "string", 1},
                                                       {"RowIndex", "string", 1},
                                                       {"ColumnIndex", "string", 1},
                                                       {"PersonBased", "int", 0}})
        // 3. Check Joins
        joins = self.Joins
        if joins <> null then
            self.CheckTable(joins, "Joins", {{"Join Name", "string", 1},
                                             {"Left Table", "string", 1},
                                             {"Left Table ID", "string", 1},
                                             {"Right Table", "string", 1},
                                             {"Right Table ID", "string", 1}})
        // 4. Check Source Keys
        src_keys = self.SourceKeys
        if src_keys <> null then
            self.CheckTable(src_keys, "SourceKeys", {{"Key", "string", 1},
                                                     {"Values", "string", 1}})
    endItem


    // Macro to add matrix source independently
    macro "AddMatrixSource"(spec) do
        // Required spec options are 'SourceName', 'File'
        // Optional spec options 'RowIndex', 'ColIndex', 'PersonBased'
        spec = self.GetOptionsArray(spec, "Choice Model Sources: Argument passed to AddMatrixSource() is not an option array")

        // Check if source is already defined. If yes, throw a message
        srcName = self.GetString(spec.SourceName, "Choice Model Sources: 'SourceName' option passed to AddMatrixSource() is either missing or is not a string")
        chk = self.CheckSource(srcName)
        if chk then
            Throw("Choice Model Sources: Matrix Source '" + srcName + "' sent to AddMatrixSource() already defined")

        // Check Matrix file that is passed
        file = self.GetString(spec.File, "Choice Model Sources: 'File' option passed to AddMatrixSource() is either missing or is not a string")
        if !GetFileInfo(file) then
            Throw("Choice Model Sources: File " + spec.File + " sent to AddMatrixSource() does not exist.")

        pth = SplitPath(file)
        if pth[4] <> ".mtx" then
            Throw("Choice Model Sources: File " + spec.File + " sent to AddMatrixSource() is not of type *.mtx")

        self.MatrixSources.Name = self.MatrixSources.Name + {srcName}
        self.MatrixSources.File = self.MatrixSources.File + {file}
        
        // The indices if provided will be checked when the sources are added to the mdl file
        // Set Row/Col index to base index if unspecified
        m = OpenMatrix(file,)
        {rowIndex, colIndex} = GetMatrixBaseIndex(m)
        m = null

        rIdx = self.GetStringOrNull(spec.RowIndex, "Choice Model Sources: 'RowIndex' option passed to AddMatrixSource() is not a string")
        if rIdx <> null then
            rowIndex = rIdx    
        self.MatrixSources.RowIndex = self.MatrixSources.RowIndex + {rowIndex}
        
        cIdx = self.GetStringOrNull(spec.ColIndex, "Choice Model Sources: 'ColIndex' option passed to AddMatrixSource() is not a string")
        if cIdx <> null then
            colIndex = cIdx    
        self.MatrixSources.ColumnIndex = self.MatrixSources.ColumnIndex + {colIndex}
        
        // Person Based Flag
        if spec.PersonBased <> null then
            personBased = self.GetNumericValue(spec.PersonBased, "Choice Model Sources: 'PersonBased' option passed to AddMatrixSource() is not numeric")
        flag = personBased >= 1
        self.MatrixSources.PersonBased = self.MatrixSources.PersonBased + {flag}    
    endItem


    // Macro to add table source independently
    macro "AddTableSource"(spec) do
        // Required spec options are 'SourceName', 'IDField'. 
        // One of 'File' or 'JoinSpec' array
        // Join Spec Array has options 'LeftFile', 'RightFile', 'LeftID', 'RightID'
        spec = self.GetOptionsArray(spec, "Choice Model Sources: Argument passed to AddTableSource() is not an option array")
        file = self.GetStringOrNull(spec.File, "Choice Model Sources: 'File' option passed to AddTableSource() is not a string")
        JSpec = spec.JoinSpec
        if JSpec <> null then
            JSpec = self.GetOptionsArray(JSpec, "Choice Model Sources: Argument 'JSpec' passed to AddTableSource() is not an option array")    
        
        if file = null and JSpec = null then
            Throw("Choice Model Sources: No 'File' or 'JoinSpec' option sent to AddTableSource()")

        if file <> null and JSpec <> null then
            Throw("Choice Model Sources: Both 'File' and 'JoinSpec' option sent to AddTableSource(). Use only one option.")

        // Check if source is already defined. If yes, throw a message
        srcName = self.GetString(spec.SourceName, "Choice Model Sources: 'SourceName' option passed to AddTableSource() is either missing or is not a string")
        chk = self.CheckSource(srcName)
        if chk then
            Throw("Choice Model Sources: Table Source '" + srcName + "' sent to AddTableSource() already defined")

        IDFld = self.GetString(spec.IDField, "Choice Model Sources: 'IDField' option passed to AddTableSource() is either missing or is not a string")

        // List of files to check
        if JSpec = null then
            files = {file}
        else do
            LHSFile = self.GetString(JSpec.LeftFile, "Choice Model Sources: 'JoinSpec.LeftFile' option passed to AddTableSource() is either missing or is not a string")
            RHSFile = self.GetString(JSpec.RightFile, "Choice Model Sources: 'JoinSpec.RightFile' option passed to AddTableSource() is either missing or is not a string")
            files = {LHSFile, RHSFile}
        end
        
        // Check files
        for f in files do
            if !GetFileInfo(f) then
                Throw("Choice Model Sources: File " + f + " sent to AddTableSource() does not exist.")

            pth = SplitPath(f)
            if Lower(pth[4]) <> ".bin" and Lower(pth[4]) <> ".dbf" and Lower(pth[4]) <> ".csv" and Lower(pth[4]) <> ".asc" then
                Throw("Choice Model Sources: File " + f + " sent to AddTableSource() is not a FFB, FFA, DBASE or CSV file")    
        end

        if JSpec <> null then do
            pthL = SplitPath(LHSFile)
            pthR = SplitPath(RHSFile)
            LeftID = self.GetString(JSpec.LeftID, "Choice Model Sources: 'JoinSpec.LeftID' option passed to AddTableSource() is either missing or is not a string")
            RightID = self.GetString(JSpec.RightID, "Choice Model Sources: 'JoinSpec.RightID' option passed to AddTableSource() is either missing or is not a string")
            self.Joins.[Join Name] = self.Joins.[Join Name] + {srcName}
            self.Joins.[Left Table] = self.Joins.[Left Table] + {pthL[3]}
            self.Joins.[Right Table] = self.Joins.[Right Table] + {pthR[3]}
            self.Joins.[Left Table ID] = self.Joins.[Left Table ID] + {LeftID}    // IDs checked when source is opened
            self.Joins.[Right Table ID] = self.Joins.[Right Table ID] + {RightID}
            self.Joins.LHSFile = self.Joins.LHSFile + {LHSFile}
            self.Joins.RHSFile = self.Joins.RHSFile + {RHSFile}
        end

        self.TableSources.Name = self.TableSources.Name + {srcName}
        self.TableSources.IDField = self.TableSources.IDField + {IDFld} // Will be checked when source will be opened
        self.TableSources.File = self.TableSources.File + {file}
    endItem


    private macro "AddPersonBasedFlags" do
        if self.MatrixSources <> null and self.MatrixSources.PersonBased = null then do // There are matrix sources but no PersonBased column
            nItems = self.MatrixSources.Name.Length
            dim a[nItems]
            for i = 1 to nItems do
                a[i] = 0
            end
            self.MatrixSources.PersonBased = CopyArray(a)
        end
    endItem


    private macro "CheckTable"(option, option_name, colSpec) do
        for i = 1 to colSpec.length do
            colName = colSpec[i][1]
            type = colSpec[i][2]
            isReq = colSpec[i][3]
            column = option.(colName)
            
            if isReq then do
                ErrMsg = "\'" + option_name + "\'' table is missing column \'" + colName + "\' OR \n\'" + option_name + "." + colName + "\' option is missing"
                if column = null then
                    Throw(ErrMsg)
            end
            
            if column <> null then do
                ErrMsg = "\'" + option_name + "." + colName + "\' is not an array"
                self.CheckOptionType(column, "array", ErrMsg)
                
                ErrMsg1 = "\'" + option_name + "\'' table has missing values in column \'" + colName + "'"
                ErrMsg2 = "\'" + option_name + "." + colName + "\' is not of type \'" + type + "\'"
                for val in column do
                    if val = null and isReq then
                        Throw(ErrMsg1)
                    if val <> null and TypeOf(val) <> type then
                        Throw(ErrMsg2)    
                end
            end
        end
    enditem


    private macro "ExpandSources" do
        keys_col = self.SourceKeys.Key         // Key value (e.g. {P})
        vals_col = self.SourceKeys.Values      // Collection of all values represented by the key (e.g. AM, PM, MD, NT)
        for i = 1 to keys_col.length do
            key = keys_col[i]
            val = vals_col[i]
            self.ExpandTableSources(key, val)
            self.ExpandMatrixSources(key, val)           
        end
    enditem


    private macro "ExpandTableSources"(key, val) do
        src_names = self.TableSources.Name
        ids = self.TableSources.IDField
        subs = ParseString(val, ", ")
        expanded_table_srcs = null
        
        for i = 1 to src_names.length do
            src_name = src_names[i]
            src_id = ids[i]
            if src_name contains key then do
                for sub in subs do
                    new_name = Substitute(src_name, key, sub,)
                    expanded_table_srcs.Name = expanded_table_srcs.Name + {new_name}
                    expanded_table_srcs.IDField = expanded_table_srcs.IDField + {src_id}
                end
            end
            else do // No need to expand and replace
                expanded_table_srcs.Name = expanded_table_srcs.Name + {src_name}
                expanded_table_srcs.IDField = expanded_table_srcs.IDField + {src_id}     
            end
        end
        self.TableSources = CopyArray(expanded_table_srcs) // Replace class variable with expanded list
    enditem


    private macro "ExpandMatrixSources"(key, val) do
        src_names = self.MatrixSources.Name
        ridxs = self.MatrixSources.RowIndex
        cidxs = self.MatrixSources.ColumnIndex
        flags = self.MatrixSources.PersonBased
        subs = ParseString(val, ", ")
        expanded_matrix_srcs = null
        
        for i = 1 to src_names.length do
            src_name = src_names[i]
            ridx = ridxs[i]
            cidx = cidxs[i]
            personBased = flags[i]
            
            if src_name contains key then do
                for sub in subs do
                    new_name = Substitute(src_name, key, sub,)
                    expanded_matrix_srcs.Name = expanded_matrix_srcs.Name + {new_name}
                    expanded_matrix_srcs.RowIndex = expanded_matrix_srcs.RowIndex + {ridx}
                    expanded_matrix_srcs.ColumnIndex = expanded_matrix_srcs.ColumnIndex + {cidx}
                    expanded_matrix_srcs.PersonBased = expanded_matrix_srcs.PersonBased + {personBased}
                end
            end
            else do // No need to expand and replace
                expanded_matrix_srcs.Name = expanded_matrix_srcs.Name + {src_name}
                expanded_matrix_srcs.RowIndex = expanded_matrix_srcs.RowIndex + {ridx}
                expanded_matrix_srcs.ColumnIndex = expanded_matrix_srcs.ColumnIndex + {cidx}
                expanded_matrix_srcs.PersonBased = expanded_matrix_srcs.PersonBased + {personBased}     
            end
        end
        self.MatrixSources = CopyArray(expanded_matrix_srcs) // Replace class variable with expanded list
    enditem


    // Append file names to the sources
    macro "GetSourceFileNames"(Args) do
        tblSrcs = self.TableSources
        if tblSrcs <> null then do
            files = self.GetFileNames(Args, tblSrcs.Name, "Table")
            tblSrcs.File = CopyArray(files)
        end

        mtxSrcs = self.MatrixSources
        if mtxSrcs <> null then do
            files = self.GetFileNames(Args, mtxSrcs.Name, "Matrix")
            mtxSrcs.File = CopyArray(files)
        end

        joins = self.Joins
        if joins <> null then do
            filesL = self.GetFileNames(Args, joins.[Left Table], "Table")
            filesR = self.GetFileNames(Args, joins.[Right Table], "Table")
            joins.LHSFile = CopyArray(filesL)
            joins.RHSFile = CopyArray(filesR)
        end
    endItem


    private macro "GetFileNames"(Args, srcNames, type) do
        files = null
        for i = 1 to srcNames.length do
            fn = self.GetFileName(Args, srcNames[i], type)
            files = files + {fn}
        end
        Return(files)
    endItem


    private macro "GetFileName"(Args, arg, type) do
        // Remove leading and trailing brackets
        str = ParseString(arg, "[]")
        argName = str[1]
        file = Args.(argName)
        pth = SplitPath(file)
        if type = 'Matrix' then do
            if file <> null then do // Need to check here if file is present. Opening source will yield an error. (Better for multiple model files)
                ErrMsg = "Matrix Source \'" + arg + "\' is not a TransCAD matrix (MTX) file"
                if Lower(pth[4]) <> ".mtx" then
                    Throw(ErrMsg)
            end    
        end
        if type = 'Table' then do
            if file <> null then do // Can be null if this is a joined view spec. But if it is not null, it better be one of the 4 types below.
                ErrMsg = "Table Source \'" + arg + "\' is not a FFB, FFA, DBASE or CSV file"
                if Lower(pth[4]) <> ".bin" and Lower(pth[4]) <> ".dbf" and Lower(pth[4]) <> ".csv" and Lower(pth[4]) <> ".asc" then
                    Throw(ErrMsg)
            end    
        end
        Return(file)   
    enditem


    macro "CheckSource"(srcName) do
        tblSrcs = self.TableSources
        mtxSrcs = self.MatrixSources
        pos = ArrayPosition(tblSrcs.Name, {srcName},)
        pos1 = ArrayPosition(mtxSrcs.Name, {srcName},)
        if pos = 0 and pos1 = 0 then
            Return(0)
        else
            Return(1) 
    endItem

    
    macro "OpenSource"(srcName) do
        srcInfo = self.GetSourceInfo(srcName)
        if srcInfo = null then
            Throw("Unable to open source \'" + srcName + "\'")
        if srcInfo.Type = "Matrix" then
            ret = self.OpenMatrixSource(srcInfo)
        else if srcInfo.Type = "Table" and  srcInfo.JoinedView <> 1 then
            ret = self.OpenTableSource(srcInfo)
        else if srcInfo.Type = "Table" and  srcInfo.JoinedView = 1 then
            ret = self.OpenJoinedSource(srcInfo)
        else
            Throw("Cannot open source \'" + src + "\'. Unknown source type.")
        
        Return(ret)         // Either a matrix handle or an open view name      
    enditem


    macro "GetSourceInfo"(srcName) do
        tblSrcs = self.TableSources
        mtxSrcs = self.MatrixSources
        pos = ArrayPosition(tblSrcs.Name, {srcName},)
        pos1 = ArrayPosition(mtxSrcs.Name, {srcName},)
        
        ret = null        
        if pos > 0 then do
            ret.Name = tblSrcs.Name[pos]
            ret.IDField = tblSrcs.IDField[pos]
            ret.Type = "Table"
            ret.File = tblSrcs.File[pos]
            if ret.File = null then do
                ret.JoinedView = 1
                jNames = self.Joins.[Join Name]
                if ArrayPosition(jNames, {srcName},) = 0 then
                    Throw("Source \'" + srcName + "\' not defined in the \'TableSources\' argument.")
            end
        end
        else if pos1 > 0 then do
            ret.Name = mtxSrcs.Name[pos1]
            ret.RowIndex = mtxSrcs.RowIndex[pos1]
            ret.ColIndex = mtxSrcs.ColumnIndex[pos1]
            ret.File = mtxSrcs.File[pos1]
            ret.Type = "Matrix"
            if mtxSrcs.PersonBased <> null then
                ret.PersonBased = mtxSrcs.PersonBased[pos1]
        end
        else
            Throw("Source \'" + srcName + "\' not defined in the \'[Table Sources]\' or \'MatrixSources\' arguments.")

        Return(ret)
    enditem


    private macro "OpenMatrixSource"(srcInfo) do
        mtx_file = srcInfo.File
        info = GetFileInfo(mtx_file)
        if !info then
            Throw("Matrix source file \'" + srcInfo.Name + "\' used in the model specification is missing.")
        
        m = OpenMatrix(mtx_file,)
        {ridxs, cidxs} = GetMatrixIndexNames(m)
        
        pos = ArrayPosition(ridxs, {srcInfo.RowIndex},)
        if pos = 0 then do
            Throw("There is no Row Index named \'" + srcInfo.RowIndex + "\' in Matrix source file \'" + srcInfo.Name + "\'.")
            m = null
        end
        
        pos = ArrayPosition(cidxs, {srcInfo.ColIndex},)
        if pos = 0 then do
            Throw("There is no Column Index named \'" + srcInfo.ColIndex + "\' in Matrix source file \'" + srcInfo.Name + "\'.")
            m = null
        end
        Return(m)
    endItem


    private macro "OpenTableSource"(srcInfo) do
        info = GetFileInfo(srcInfo.File)
        if !info then
            Throw("File \'" + srcInfo.Name + "\' used in the model specification is missing.")
        
        vw = self.GetTableView(srcInfo.File, srcInfo.Name)
        {flds, specs} = GetFields(vw,)
        // Remove leading and trailing brackets from field names
        flds = flds.Map(do (f)
                         fOut = if Left(f,1) = "[" then SubString(f, 2, StringLength(f) - 2) else f
                         Return(fOut)
                         end)
        pos = ArrayPosition(flds, {srcInfo.IDField},)
        if pos = 0 then do
            Throw("There is no field named \'" + srcInfo.IDField + "\' in source file \'" + srcInfo.Name + "\'.")
            CloseView(vw)
        end
        Return(vw)
    endItem


    private macro "GetTableView"(file, desired_vw) do
        pth = SplitPath(file)
        if Lower(pth[4]) = ".bin" then
            type = "FFB"
        else if Lower(pth[4]) = ".dbf" then
            type = "DBASE"
        else if Lower(pth[4]) = ".asc" then
            type = "FFA"
        else if Lower(pth[4]) = ".csv" then
            type = "CSV"
    
        if RunMacro("Parallel.IsEngine") then do                    // When running in parallel engine
            if  OpenOpts.[Read Only] = null then 
                OpenOpts.[Read Only] = "True"                       // open  as read-only
            if  OpenOpts.[AttributeTableIsWritable] = null then 
                OpenOpts.[AttributeTableIsWritable] = "False"       // open attributes as read-and-write
            if  OpenOpts.[Shared] = null then 
                OpenOpts.[Shared] = "True"                          
        end
        
        vw = OpenTable(desired_vw, type, {file,}, OpenOpts)
        Return(vw)    
    endItem


    private macro "OpenJoinedSource"(srcInfo) do
        joins = self.Joins
        joinNames = joins.[Join Name]
        lhsVws = joins.[Left Table]
        rhsVws = joins.[Right Table]
        lhsIDs = joins.[Left Table ID]
        rhsIDs = joins.[Right Table ID]
        lhsFiles = joins.LHSFile
        rhsFiles = joins.RHSFile

        pos = ArrayPosition(joinNames, {srcInfo.Name},)
        stack_pos = {pos}

        // Add the joined view positions to the stack. They will be processed in LIFO in the next loop
        c = 1
        while c <= stack_pos.length do
            pos = stack_pos[c]
            lhsSrc = lhsVws[pos]
            rhsSrc = rhsVws[pos]
            lhsFile = lhsFiles[pos]
            rhsFile = rhsFiles[pos]
            if lhsFile = null then do // Not a file and therefore maybe another joined view or a mistake
                temp_pos = ArrayPosition(joinNames, {lhsSrc},)
                if temp_pos = 0 then // Mistake
                    Throw("Could not find " + lhsSrc + " in list of joined views")
                else do // Another joined view
                    if ArrayPosition(stack_pos, {temp_pos},) = 0 then
                        stack_pos = stack_pos + {temp_pos}
                end
            end
            if rhsFile = null then do // Not a file and therefore maybe another joined view or a mistake
                temp_pos = ArrayPosition(joinNames, {rhsSrc},)
                if temp_pos = 0 then // Mistake
                    Throw("Could not find " + rhs_src + " in list of joined views")
                else // Another joined view
                    if ArrayPosition(stack_pos, {temp_pos},) = 0 then
                        stack_pos = stack_pos + {temp_pos}
            end
            c = c + 1
        end

        // Process the stack and make joins
        vws = null
        for i = stack_pos.length to 1 step -1 do
            pos = stack_pos[i]
            lhsSrc = lhsVws[pos]
            rhsSrc = rhsVws[pos]
            lhsFile = lhsFiles[pos]
            rhsFile = rhsFiles[pos]

            // Open tables if views do not exist
            if vws.(lhsSrc) = null then do // Open Table
                vws.(lhsSrc) = self.GetTableView(lhsFile, lhsSrc)
                if vws.(lhsSrc) = null then
                    Throw("Could not open file " + lhsFile)
            end
            if vws.(rhsSrc) = null then do // Open Table
                vws.(rhsSrc) = self.GetTableView(rhsFile, rhsSrc)
                if vws.(rhsSrc) = null then
                    Throw("Could not open file " + rhsFile)
            end

            // Get Field Specs
            lhsFld = self.CheckFieldValidity(vws.(lhsSrc), lhsIDs[pos])
            rhsFld = self.CheckFieldValidity(vws.(rhsSrc), rhsIDs[pos])
            lhsSpec = GetFieldFullSpec(vws.(lhsSrc), lhsFld)
            rhsSpec = GetFieldFullSpec(vws.(rhsSrc), rhsFld)

            // Make the join. Check for fields first
            jvm = joinNames[pos]
            vws.(jvm) = JoinViews(jvm, lhsSpec, rhsSpec,)   
        end

        // Close all views exceot the final desired join
        for i = 1 to vws.length - 1 do
            CloseView(vws[i][2])
        end
    
        ret_vw = joinNames[stack_pos[1]]
        Return(ret_vw)
    endItem


    done do
        self.MatrixSources = null
        self.TableSources = null
        self.SourceKeys = null  
        self.Joins = null    
    endItem

endClass
