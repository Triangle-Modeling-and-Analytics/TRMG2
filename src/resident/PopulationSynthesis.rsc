/*
    * Macro that performs population synthesis using the TransCAD (9.0) built-in procedure. 
        * Marginal Data - Disaggregated SED Marginals (by TAZ)
        * HH Dimensions are:
            * HH By Size - 1, 2, 3 and 4+
            * HH By Workers - 0, 1, 2 and 3+
            * HH By Income Category - 1: [0, 35000); 2: [35000, 75000); 3. [75000, 150000); 4. 150000+
        * For Persons, a match to the total population (HH_POP) by TAZ is attempted via the IPU (Iterational Proportional Update) option using:
            * Age - One category comprising all age groups.
*/
Macro "Population Synthesis"(Args)
    on escape, error, notfound do
        ErrorMsg = GetLastError()
        ret_value = 0
        goto quit
    end
    // Set up and run the synthesis
    o = CreateObject("PopulationSynthesis")
    
    // Define Seed Data. Specify relationship between HH file and TAZ and between HH and Person file
    o.HouseholdFile({FileName: Args.[PUMS HH Seed], Filter: "NP <= 10", ID: "HHID", MatchingID: "PUMA", WeightField: "WGTP"})
    o.PersonFile({FileName: Args.[PUMS Person Seed], ID: "PersonID", HHID: "HHID"})
    
    // Define the marginals data (Disaggregated SED marginals)
    marginalData = {FileName: Args.SEDMarginals, Filter: "HH > 0", ID: "TAZ", MatchingID: "PUMA5"}
    o.MarginalFile(marginalData)     
    o.IPUMarginalFile(marginalData)             

    // ***** HH Dimensions *****
    // HH by Size: Define TAZ marginal fields and corresponding values in the seed data
    // Add Marginal Data Spec
    // 'Field': Field from HH seed file for matching (e.g. NPis the HHSize field in the PUMS HH seed)
    // 'Value': The above array, that specifies the marginal fields and how they are mapped to the seed field
    // 'NewFieldName': The field name in the synthesized outout HH file for this variable
    // Also specify the matching field in the seed data
    HHDimSize = {{Name: "HH_size1", Value: {1, 2}}, 
                 {Name: "HH_size2", Value: {2, 3}}, 
                 {Name: "HH_size3", Value: {3, 4}}, 
                 {Name: "HH_size4", Value: {4, 99}}}
    HHbySizeSpec = {Field: "NP", Value: HHDimSize, NewFieldName: "HHSize"}
    o.AddHHMarginal(HHbySizeSpec)

    // HH by Income (4 categories): Define TAZ marginal fields and corresponding values in the seed data
    HHDimInc = {{Name: "HH_incl" , Value: 1}, 
                {Name: "HH_incml", Value: 2}, 
                {Name: "HH_incmh", Value: 3}, 
                {Name: "HH_inch",  Value: 4}}
    HHbyIncSpec = {Field: "IncomeCategory", Value: HHDimInc, NewFieldName: "IncomeCategory"}
    o.AddHHMarginal(HHbyIncSpec)

    // HH by Number of Workers
    HHDimWrk =   {{Name: "HH_wrk0", Value: {0, 1}}, 
                  {Name: "HH_wrk1", Value: {1, 2}}, 
                  {Name: "HH_wrk2", Value: {2, 3}}, 
                  {Name: "HH_wrk3", Value: {3, 99}}}
    HHbyWrkSpec = {Field: "NumberWorkers", Value: HHDimWrk, NewFieldName: "NumberWorkers"}
    o.AddHHMarginal(HHbyWrkSpec)


    // ***** Add marginals for IPU *****
    // Typically, a good idea to include all of the above HH marginals in the IPU as well
    o.AddIPUHouseholdMarginal(HHbySizeSpec)
    o.AddIPUHouseholdMarginal(HHbyIncSpec)
    o.AddIPUHouseholdMarginal(HHbyWrkSpec)

    // ***** Person Dimensions *****
    // These can only be specified for the IPU procedure
    // Since we want to control HH_Pop for each TAZ, we create one category (using all Age ranges) and match that to the total.
    PersonDim = {{Name: "HH_POP" , Value: {0, 100}}}
    o.AddIPUPersonMarginal({Field: "AGEP", Value: PersonDim, NewFieldName: "Age"})

    // ***** Outputs *****
    // A general note on IPU: 
    // The IPU procedure generally creates a set of weights, one for each PUMA zones as opposed to a single weight field without IPU
    // These weight fields are used for sampling from the seed
    // Optional outputs include: The IPUIncidenceFile and one weight table for each PUMA
    o.OutputHouseholdsFile = Args.[Synthesized HHs]
    o.ReportExtraHouseholdField("PUMA", "PUMA")
    o.OutputPersonsFile = Args.[Synthesized Persons]
    o.ReportExtraPersonsField("SEX", "Gender") // Add extra field from Person Seed and change the name
    
    // Optional IPU by-products
    outputFolder = Args.[Output Folder] + "\\resident\\population_synthesis\\"
    o.IPUIncidenceOutputFile = outputFolder + "IPUIncidence.bin"
    o.ExportIPUWeights(outputFolder + "IPUWeights")
    ret_value = o.Run()

   quit:
    on error, notfound, escape default
    if !ret_value then do
        if ErrorMsg <> null then
            AppendToLogFile(0, ErrorMsg)
    end
    Return(ret_value)
endMacro


Macro "PopSynth Post Process"(Args)
    on escape, error, notfound do
        ErrorMsg = GetLastError()
        ret_value = 0
        goto quit
    end

    // Write Block and BlockGroup info in output HH table
    vw_hh = OpenTable("HH", "FFB", {Args.[Synthesized HHs],})
    vw_per = OpenTable("Pop", "FFB", {Args.[Synthesized Persons],})
    
    // Create Balloon Help on synthesized tables
    RunMacro("Set Balloon Help", vw_hh, vw_per)
    BuildInternalIndex(GetFieldFullSpec(vw_hh, "HouseholdID"))
    BuildInternalIndex(GetFieldFullSpec(vw_hh, "TAZ"))
    BuildInternalIndex(GetFieldFullSpec(vw_per, "PersonID"))
    BuildInternalIndex(GetFieldFullSpec(vw_per, "HouseholdID"))

    // Generate output tabulations
    RunMacro("Generate Tabulations", vw_hh, vw_per, Args.[Synthesized Tabulations])
    ret_value = 1
 quit:
    on escape, error, notfound default
    if !ret_value then do
        if ErrorMsg <> null then
            AppendToLogFile(0, ErrorMsg)
    end
    Return(ret_value)
endMacro


Macro "Set Balloon Help"(vw_hh, vw_per)
    // HH Field Descriptions
    desc = null
    desc.ZoneID = "TRM TAZ ID"
    desc.IncomeCategory = "Household Income Category:|1. Income [0, 35K)|2. Income [35K, 70K)|3. Income [70K, 150K)| 4. Income 150K+"
    strct = GetTableStructure(vw_hh, {"Include Original" : "True"})
    for i = 1 to strct.length do
        fld_name = strct[i][1]
        strct[i][8] = desc.(fld_name)
    end
    ModifyTable(vw_hh, strct)
    
    // Person Field descriptions
    desc = null
    desc.Gender = "Gender:|1. Male|2. Female"
    strct = GetTableStructure(vw_per, {"Include Original" : "True"})
    for i = 1 to strct.length do
        fld_name = strct[i][1]
        strct[i][8] = desc.(fld_name)
    end
    ModifyTable(vw_per, strct)
endMacro


Macro "Generate Tabulations"(vw_hh, vw_per, outFile)
    // Create Expressions on output HH for tabulations
    specs = null
    specs = {{Fields: {"HH_size1", "hh_size2", "hh_size3", "hh_size4"}, MatchingField: "HHSize", Levels: {1,2,3,4}},
             {Fields: {"HH_wrk0", "hh_wrk1", "hh_wrk2", "hh_wrk3"},     MatchingField: "NumberWorkers", Levels: {0,1,2,3}},
             {Fields: {"HH_incl", "HH_incml", "HH_incmh", "HH_inch"},   MatchingField: "IncomeCategory", Levels: {1,2,3,4}}
             }
    aggflds = RunMacro("Create Output Expressions", vw_hh, specs)
    aggflds = aggflds + {{"HHSize", "sum",}} // For HH_Pop

    // Aggregate HH Data
    vw_agg1 = AggregateTable("HHTotals", vw_hh + "|", "MEM", "Agg1", "ZoneID", aggflds, null)
    ExportView(vw_agg1 + "|", "FFB", outFile,,)
    CloseView(vw_agg1)

    // Change field name in final tabulation file
    obj = CreateObject("AddTables", {TableName: outFile})
    vw = obj.TableView
    modify = CreateObject("CC.ModifyTableOperation", vw)
    modify.ChangeField("HHSize", {Name: "HH_Pop"})
    modify.Apply()
    obj = null
endMacro


// Generates formula fields for tabulations
Macro "Create Output Expressions"(vw_hh, specs)
    aggflds = null
    for spec in specs do
        flds = spec.Fields
        keyFld = spec.MatchingField
        bounds = spec.Levels
        nClasses = flds.length
        for i = 1 to nClasses - 1 do
            CreateExpression(vw_hh, flds[i], "if " + keyFld + " = " + String(bounds[i]) + " then 1 else 0",)
            aggflds = aggflds + {{flds[i], "sum",}}
        end
        CreateExpression(vw_hh, flds[nClasses], "if " + keyFld + " >= " + String(bounds[nClasses]) + " then 1 else 0",)
        aggflds = aggflds + {{flds[nClasses], "sum",}}
    end
    Return(aggflds)
endMacro
