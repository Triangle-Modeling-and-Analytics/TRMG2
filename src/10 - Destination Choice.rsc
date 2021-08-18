/*

*/

Macro "Destination Choice" (Args)

    RunMacro("Split Employment by Earnings", Args)
    RunMacro("DC Attractions", Args)

    return(1)
endmacro

/*
The resident DC model needs the low-earning fields for the attraction models.
For work trips, this helps send low income households to low earning jobs.
*/

Macro "Split Employment by Earnings" (Args)

    se_file = Args.SE
    se_vw = OpenTable("se", "FFB", {se_file})
    a_fields = {
        {"Industry_EL", "Real", 10, 2, , , , "Low paying industry jobs"},
        {"Industry_EH", "Real", 10, 2, , , , "High paying industry jobs"},
        {"Office_EL", "Real", 10, 2, , , , "Low paying office jobs"},
        {"Office_EH", "Real", 10, 2, , , , "High paying office jobs"},
        {"Retail_EL", "Real", 10, 2, , , , "Low paying retail jobs"},
        {"Retail_EH", "Real", 10, 2, , , , "High paying retail jobs"},
        {"Service_RateLow_EL", "Real", 10, 2, , , , "Low paying service_rl jobs"},
        {"Service_RateLow_EH", "Real", 10, 2, , , , "High paying service_rl jobs"},
        {"Service_RateHigh_EL", "Real", 10, 2, , , , "Low paying service_rh jobs"},
        {"Service_RateHigh_EH", "Real", 10, 2, , , , "High paying service_rh jobs"}
    }
    RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})

    input = GetDataVectors(
        se_vw + "|",
        {"Industry", "Office", "Retail", "Service_RateLow", "Service_RateHigh", "PctHighPay"},
        {OptArray: "true"}
    )
    output.Industry_EH = input.Industry * input.PctHighPay/100
    output.Industry_EL = input.Industry * (1 - input.PctHighPay/100)
    output.Office_EH = input.Office * input.PctHighPay/100
    output.Office_EL = input.Office * (1 - input.PctHighPay/100)
    output.Retail_EH = input.Retail * input.PctHighPay/100
    output.Retail_EL = input.Retail * (1 - input.PctHighPay/100)
    output.Service_RateLow_EH = input.Service_RateLow * input.PctHighPay/100
    output.Service_RateLow_EL = input.Service_RateLow * (1 - input.PctHighPay/100)
    output.Service_RateHigh_EH = input.Service_RateHigh * input.PctHighPay/100
    output.Service_RateHigh_EL = input.Service_RateHigh * (1 - input.PctHighPay/100)
    SetDataVectors(se_vw + "|", output, )
endmacro

/*

*/

Macro "DC Attractions" (Args)

    se_file = Args.SE
    rate_file = Args.ResDCAttrRates

    se_vw = OpenTable("se", "FFB", {se_file})
    {drive, folder, name, ext} = SplitPath(rate_file)
    RunMacro("Create Sum Product Fields", {
        view: se_vw, factor_file: rate_file,
        field_desc: "Resident DC Attractions|See " + name + ext + " for details."
    })

    CloseView(se_vw)
endmacro