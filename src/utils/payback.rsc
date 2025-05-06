Macro "Open Payback Period Tool Dbox" (Args)
	RunDbox("Payback Period Tool", Args)
endmacro

dBox "Payback Period Tool" (Args) center,center,85,20 toolbox NoKeyboard Title:"Project Metrics"

	
	
	init do
		static ref_scen, new_scen, sub_poly
		// scendbd = "Y:\\TRM Model\\V5 Model 2012-03-20\\TRM v5 Model\\Setups\\2040 LRTP\\Highway Intensive\\Output\\Map Suite\\Comparison to Deficiency Analysis EC\\LinkComparison.bin"
		buffer1 = 4
		buffer2 = 2
		
	endItem

    close do
        return()
    enditem

    Text 10, 1, 15 Framed Prompt: "Reference Scenario:" Variable: ref_scen
    Button after, same, 5, 1 Prompt: "..." do
        on error, escape goto skip1
        ref_scen = ChooseDirectory("Choose reference scenario", )
        skip1:
        on error default
    enditem

    Text 10, after, 15 Framed Prompt: "New Scenario:" Variable: new_scen
    Button after, same, 5, 1 Prompt: "..." do
        on error, escape goto skip2
        new_scen = ChooseDirectory("Choose new scenario", )
        skip2:
        on error default
    enditem

/*
    Text" " 4,3,30,1 Variable:RunMacro("TCU trim filename", universedbd, 32) Framed Prompt: "Highway Universal File"


//	The Universe File Button
    
    button "Browse" 36.5, 3, 10, 1 do 


	on escape goto quit	// if user presses escape, the browse window will close without an error message
	
	if universedbd <> null then do
		universedbd = ChooseFile({{"Standard (*.dbd)", "*.dbd"}},"Select the Highway Project Universe",{,{"Initial Directory",universedbd},})
	end

	if universedbd = null then do
		universedbd = ChooseFile({{"Standard (*.dbd)", "*.dbd"}}, "Select the Highway Universe",)
	end

	quit:				// where the cancel button sends user
	on escape default		// resetting error handling to default

    enditem
*/
	


//  Project ID List Text File

	Text" " 4,5,30,1 Variable:RunMacro("TCU trim filename", projectlist, 32) Framed Prompt: "Project List"

	
	button "Browse" 36.5, 5, 10, 1 do 

	on escape goto quit	// if user presses escape, the browse window will close without an error message
	



	projectlist = ChooseFile({{"Text File (*.txt)", "*.txt"}}, "Select the Project List",)


	quit:				// where the cancel button sends user
	on escape default		// resetting error handling to default

    enditem
	
	Text" " 38,6.25,30,1 Prompt: "A simple .txt with a single column of IDs"
	
	
	





/*	
	
	// Open loaded highway network to get the list of field names
	RunMacro("G30 new map", scendbd, "False")
	
	
	// Collect the list of field names to allow user to choose which one contains the metric to summarize
	fields_array = GetFields(GetView(), "All")
	arraylength = fields_array.length
	dim fieldnames[arraylength]
	fieldnames = fields_array[1]

	// Close the map
	CloseMap(GetMap())

	// Enable the drop down list
	EnableItem("fieldlist")
*/	
	

	

	
/*	
	// Drop down list of field names
	
	Popdown Menu "fieldlist" 4, 11, 15, 10 prompt: "Loaded Highway Metric to Aggregate" list: fieldnames variable: dropindex Disabled do

		metric = fieldnames[dropindex]
		
		
		// The following logic handles the possible selection of AB/BA fields
		// If one is chosen, then the alternate field name is created
		
		if Left(metric, 2) = "AB" then do
			dualized="Dualized"
			metricAB = metric
			metricBA = "BA" + Right(metric, StringLength(metric) - 2)
		end
		if Left(metric, 2) = "BA" then do 
			dualized="Dualized"
			metricBA = metric
			metricAB = "AB" + Right(metric, StringLength(metric) - 2)
		end
		if Left(metric, 2) <> "BA" and Left(metric, 2) <> "AB" then dualized = "Non-Dualized"
	
     endItem

*/

	 
	// Dualized field info text box
	//Text "" 20, 11, 20, 1 Variable:dualized
	
	
	
	
	// Specify buffer distance (miles)
	
	Edit Real "buffer" 4, 13, 4, 1 Prompt: "Tier 1/2 Buffer Radius (miles):" Variable: buffer1
	Edit Real "buffer" 4, 14.5, 4, 1 Prompt: "Tier 3 Buffer Radius (miles):" Variable: buffer2
	

	//	Perform Analysis Button
	button "Aggregate" 4, 16.5, 12 do
		
		//if metric = null then ShowMessage("Select the field to aggregate")
		//else
		if buffer1 = null or buffer1 = 0 then ShowMessage("Choose non-0 Buffer Distances")
		else
		if buffer2 = null or buffer2 = 0 then ShowMessage("Choose non-0 Buffer Distances")
		else do
			
			// Can only pass 9 variables, so put the two buffer variables into an array
			dim buffers[2]
			buffers[1] = buffer1
			buffers[2] = buffer2
			
			RunMacro("Aggregate", Args, buffers, projectlist, ref_scen, new_scen)
			
		end
			
	enditem




	//	Quit Button
	button "Main Menu" 4, 18.5, 12 do
		Return(0)
	enditem
	
	
	
EndDbox











//	*****
//	MACRO
//	*****




Macro "Aggregate" (Args, buffers, projectlist, ref_scen, new_scen)

output_dir = Args.[Summary Folder] + "\\Payback Period"
RunMacro("Create Directory", output_dir)
scendbd = Args.Links
buffer1 = buffers[1]
buffer2 = buffers[2]


RunMacro("TCB Init")


// The purpose of this script is to pull highway attributes (mainly delay) from links near all LRTP/CTP projects
// In excel, this data would be manipulated to create a rank ordering of projects.



//	Close anything that might be open
	RunMacro("G30 File Close All")

// Output location (same as projectlist location)
outputText = output_dir + "\\OutputList.txt"



// Read project id list into an array

listfile = OpenFile(projectlist, "r")
idarray = ReadArray(listfile)

// Get scenario names 
parts = ParseString(ref_scen, "\\")
base_name = parts[parts.length] 
parts = ParseString(new_scen, "\\")
proj_name = parts[parts.length]

RunMacro("Compare Summary Tables",  {
            ref_scen: ref_scen,
            new_scen: new_scen
        })
// Copy the scendbd in order to calculate Primary and Secondary calculations

outputdbd = output_dir + "\\BenefitCalculation.dbd"


// If the user has indicated that the time-intensive calculations were done previously, they are skipped.

	
CopyDatabase(scendbd, outputdbd)	


// Add diff bin table
{nlyr, llyr} = GetDBLayers(outputdbd)
diff_file = Args.[Summary Folder] + "\\comparison_outputs\\output\\networks\\scenario_links.bin"
RunMacro("Join Table To Layer", outputdbd, "ID", diff_file, "ID")

// Modify the table structure to add desired fields

outputdataview = OpenTable("outputdataview", "FFB", {output_dir + "\\BenefitCalculation.bin",})

strct = GetTableStructure(outputdataview)

for i = 1 to strct.length do

	// Copy the current name to the end of strct.  GetTableRestructure returns an array with 11 elements.  ModifyTable needs a 12th: original field name.
	// So, for all the pre-existing fields, you loop through and add the name onto the end.  New fields leave this null.
	strct[i] = strct[i] + {strct[i][1]}

end


// This is where you add fields by appending them onto strct


strct = strct + {{"ABPrimBen", "Real", 12, 2, "False", , , "Delay change from improvements on this link", , , , null}}
strct = strct + {{"BAPrimBen", "Real", 12, 2, "False", , , "Delay change from improvements on this link", , , , null}}
strct = strct + {{"ABSecBen", "Real", 12, 2, "False", , , "Delay change from improvements on other links", , , , null}}
strct = strct + {{"BASecBen", "Real", 12, 2, "False", , , "Delay change from improvements on other links", , , , null}}





ModifyTable(outputdataview, strct)


CloseView(outputdataview)















// Create a map with the difference highway file

// GetDBInfo returns 3 things - Scope, Label of File, Revision
info = GetDBInfo(outputdbd)
scope = info[1]

// GetDBLayers returns an array of strings - each is a layer name
scenariolayers = GetDBLayers(outputdbd)


//Create a new, blank map

maptitle = "Benefit Calculation"


map = CreateMap(maptitle,{
	{"Scope",scope},
	{"Auto Project","True"}
	})

//Next, add the difference layer to the map (map name - current if blank, layer name, db location, db layer name)

	scenlLayer = AddLayer(map,scenariolayers[2],outputdbd,scenariolayers[2])
	SetLayer(scenlLayer)







// Open/Create a text file for writing

file = OpenFile(outputText, "w")







// Begin Primary/Secondary Benefit Calculation


	
// For each link, the first step is to calucate the percentage of primary and secondary benefit
//
// The change in capacity is used to approximate the proportion of primary benefit.
//     i.e. capacity increases are the result of the project
// The change in volume is used to approximate the proportion of secondary benefit.
//     i.e. volume decreases are the result of improvement in other projects
//
// Thus, the following ratio of ratios:
//
// [ (New Capacity / Old Capacity) / ( (New Capacity / Old Capacity) + (New Volume/Old Volume) * -1 ) ]
//
// This metric will determine how much of the decrease delay on the project is due to the project
// and how much is the secondary benefit from other projects.
//
// Some basic rules are also used:
// 1. If the capacity of the link stays the same or decreases, any and all benefit is secondary
// 2. If the volume of the link stays the same or increases, any and all benefit is primary
// 3. If the base volume is 0 (a new-location project), the primary benefit is null (as opposed to showing the delay getting worse
//	  going from 0 to some positive number).  There is also no secondary benefit.



// Retrive all the value vectors needed for calculation (Capacity, Volume, and change in Delay)

abbasecapvec = GetDataVector(scenlLayer + "|", "ABAMCapE_h_" + base_name, {{"Missing as Zero", "True"},{"Sort Order",{{"ID","Ascending"}}}})
babasecapvec = GetDataVector(scenlLayer + "|", "BAAMCapE_h_" + base_name, {{"Missing as Zero", "True"},{"Sort Order",{{"ID","Ascending"}}}})
abbasevolvec = GetDataVector(scenlLayer + "|", "AB_Flow_Daily_" + base_name, {{"Missing as Zero", "True"},{"Sort Order",{{"ID","Ascending"}}}})
babasevolvec = GetDataVector(scenlLayer + "|", "BA_Flow_Daily_" + base_name, {{"Missing as Zero", "True"},{"Sort Order",{{"ID","Ascending"}}}})

abpropcapvec = GetDataVector(scenlLayer + "|", "ABAMCapE_h_" + proj_name, {{"Missing as Zero", "True"},{"Sort Order",{{"ID","Ascending"}}}})
bapropcapvec = GetDataVector(scenlLayer + "|", "BAAMCapE_h_" + proj_name, {{"Missing as Zero", "True"},{"Sort Order",{{"ID","Ascending"}}}})
abpropvolvec = GetDataVector(scenlLayer + "|", "AB_Flow_Daily_" + proj_name, {{"Missing as Zero", "True"},{"Sort Order",{{"ID","Ascending"}}}})
bapropvolvec = GetDataVector(scenlLayer + "|", "BA_Flow_Daily_" + proj_name, {{"Missing as Zero", "True"},{"Sort Order",{{"ID","Ascending"}}}})

abdelaydiffvec = GetDataVector(scenlLayer + "|", "AB_Delay_Daily_diff", {{"Missing as Zero", "True"},{"Sort Order",{{"ID","Ascending"}}}})
badelaydiffvec = GetDataVector(scenlLayer + "|", "BA_Delay_Daily_diff", {{"Missing as Zero", "True"},{"Sort Order",{{"ID","Ascending"}}}})



// Create vectors to hold calculated values

abvolpercdiffvec = Vector(abbasecapvec.length, "float", {{"Constant", 0}})
bavolpercdiffvec = Vector(abbasecapvec.length, "float", {{"Constant", 0}})
abcappercdiffvec = Vector(abbasecapvec.length, "float", {{"Constant", 0}})
bacappercdiffvec = Vector(abbasecapvec.length, "float", {{"Constant", 0}})

abpercprimbenvec = Vector(abbasecapvec.length, "float", {{"Constant", 0}})
bapercprimbenvec = Vector(abbasecapvec.length, "float", {{"Constant", 0}})
abpercsecbenvec = Vector(abbasecapvec.length, "float", {{"Constant", 0}})
bapercsecbenvec = Vector(abbasecapvec.length, "float", {{"Constant", 0}})

abprimebenefitvec = Vector(abbasecapvec.length, "float", {{"Constant", 0}})
baprimebenefitvec = Vector(abbasecapvec.length, "float", {{"Constant", 0}})
absecondarybenefitvec = Vector(abbasecapvec.length, "float", {{"Constant", 0}})
basecondarybenefitvec = Vector(abbasecapvec.length, "float", {{"Constant", 0}})



// Calculate ab and ba percdiff vectors for volume and capacity

for i = 1 to abbasecapvec.length do
	
	if abbasevolvec[i] = 0 then abvolpercdiffvec[i] = 0
	else abvolpercdiffvec[i] = (abpropvolvec[i] - abbasevolvec[i]) / abbasevolvec[i]
	
	if babasevolvec[i] = 0 then bavolpercdiffvec[i] = 0
	else bavolpercdiffvec[i] = (bapropvolvec[i] - babasevolvec[i]) / babasevolvec[i]
	
	if abbasecapvec[i] = 0 then abcappercdiffvec[i] = 0
	else abcappercdiffvec[i] = (abpropcapvec[i] - abbasecapvec[i]) / abbasecapvec[i]
	
	if babasecapvec[i] = 0 then bacappercdiffvec[i] = 0
	else bacappercdiffvec[i] = (bapropcapvec[i] - babasecapvec[i]) / babasecapvec[i]
	
	






	// Calculate the ab and ba percentage of primary/secondary impact	
	
	// AB
	
	if abbasecapvec[i] = 0 then do																				// if the base capacity is 0 (new location project), no primary or secondary impact on the link
		abpercprimbenvec[i] = 0
		abpercsecbenvec[i] = 0
	end
	else if abcappercdiffvec[i] <= 0 then do																	// if the capacity stays the same or decreases, all impact is secondary
		abpercprimbenvec[i] = 0
		abpercsecbenvec[i] = 1
	end
	else if abvolpercdiffvec[i] >= 0 and abdelaydiffvec[i] <= 0 then do											// if the capacity stays the same or increases, volume stays the same or increases, and delay improves, all impact is primary on the link
		abpercprimbenvec[i] = 1																					
		abpercsecbenvec[i] = 0
	end
	else if abvolpercdiffvec[i] >= 0 and abdelaydiffvec[i] > 0 then do											// if the capacity increases, volume stays the same or increases, and delay worsens, all impact is secondary on the link
		abpercprimbenvec[i] = 0
		abpercsecbenvec[i] = 1
	end
	else do
		abpercprimbenvec[i] = abcappercdiffvec[i] / (abcappercdiffvec[i] + abvolpercdiffvec[i]*-1)				// if none of the above are true, (the capacity increases and the volume decreases), then the ratio of (%change in capacity) to (%change in capacity + %chagne in volume) is used for primary and (1-primary) = secondary
		abpercsecbenvec[i] = 1 - abpercprimbenvec[i]
	end


	// BA
	
	if babasecapvec[i] = 0 then do																				// if the base capacity is 0 (new location project), no primary or secondary impact on the link
		bapercprimbenvec[i] = 0
		bapercsecbenvec[i] = 0
	end
	else if bacappercdiffvec[i] <= 0 then do																	// if the capacity stays the same or decreases, all impact is secondary
		bapercprimbenvec[i] = 0
		bapercsecbenvec[i] = 1
	end
	else if bavolpercdiffvec[i] >= 0 and badelaydiffvec[i] <= 0 then do											// if the capacity stays the same or increases, volume stays the same or increases, and delay improves, all impact is primary on the link
		bapercprimbenvec[i] = 1																					
		bapercsecbenvec[i] = 0
	end
	else if bavolpercdiffvec[i] >= 0 and badelaydiffvec[i] > 0 then do											// if the capacity increases, volume stays the same or increases, and delay worsens, all impact is secondary on the link
		bapercprimbenvec[i] = 0
		bapercsecbenvec[i] = 1
	end
	else do
		bapercprimbenvec[i] = bacappercdiffvec[i] / (bacappercdiffvec[i] + bavolpercdiffvec[i]*-1)				// if none of the above are true, (the capacity increases and the volume decreases), then the ratio of (%change in capacity) to (%change in capacity + %chagne in volume) is used for primary and (1-primary) = secondary
		bapercsecbenvec[i] = 1 - bapercprimbenvec[i]
	end	

	





	// Calculate the prime and secondary benefits
	// Multiplying by -1 flips it so that a positive number denotes benefit and a negative number denotes decreased benefit.
	// (a negative change in delay = a positive benefit)
		
	abprimebenefitvec[i] = abpercprimbenvec[i] * abdelaydiffvec[i] * -1
	baprimebenefitvec[i] = bapercprimbenvec[i] * badelaydiffvec[i] * -1
	absecondarybenefitvec[i] = abpercsecbenvec[i] * abdelaydiffvec[i] * -1
	basecondarybenefitvec[i] = bapercsecbenvec[i] * badelaydiffvec[i] * -1

end




// Set the Primary and Secondary Benefit Field Values

SetDataVector(scenlLayer + "|", "ABPrimBen", abprimebenefitvec, {{"Sort Order",{{"ID","Ascending"}}}})
SetDataVector(scenlLayer + "|", "BAPrimBen", baprimebenefitvec, {{"Sort Order",{{"ID","Ascending"}}}})
SetDataVector(scenlLayer + "|", "ABSecBen", absecondarybenefitvec, {{"Sort Order",{{"ID","Ascending"}}}})
SetDataVector(scenlLayer + "|", "BASecBen", basecondarybenefitvec, {{"Sort Order",{{"ID","Ascending"}}}})
























//Begin selecting projects and writing IDs and benefits to a file.

for i = 1 to idarray.length do

	projvmtincr = 0																	// the project's increase in vmt (Volume * Length)
	surrprojvmtincr = 0																// the surrounding projects' increases in vmt
	percentvmt = 0																	// the percent of total vmt increase that is the project
	surrsecbenchange = 0															// this will collect the secondary benefits arround the project
	projprimebenefit = 0															// the total primary benefit on the project links themselves
	projsecbenefit = 0																// the total secondary benefit that other projects experience due to this project
	totalbenefit = 0																// primary + secondary benefits
	


	//Select the project
	
	SetLayer(scenlLayer)
	
	query = "Select * where UpdatedWithP='" + idarray[i] + "'"
	n1 = SelectByQuery ("Projects", "Several", query)

	if n1 > 0 then do
		
		
		
		// First, sum up the primary benefits on the project links
		
		abprojprimebenvec = GetDataVector(scenlLayer + "|Projects", "ABPrimBen", {{"Sort Order",{{"ID","Ascending"}}},{"Missing as Zero", "True"}})
		baprojprimebenvec = GetDataVector(scenlLayer + "|Projects", "BAPrimBen", {{"Sort Order",{{"ID","Ascending"}}},{"Missing as Zero", "True"}})
		
		for m = 1 to abprojprimebenvec.length do
			
			projprimebenefit = projprimebenefit + abprojprimebenvec[m] + baprojprimebenvec[m]
			
		end
		
		// If the total prime benefit is negative (a worsening of delay), make it 0.
		projprimebenefit = max(projprimebenefit, 0)


		
		
		
		
		
		// Test to see if the project is Tier 1 or 2 (FCGROUP = 1 or 2)
				
		fcgroup = GetDataVector(scenlLayer + "|Projects", "HCMType", {{"Sort Order",{{"ID","Ascending"}}},{"Missing as Zero", "True"}})
		
		roadclass = "Minor"
		
		for m = 1 to fcgroup.length do
			
			if fcgroup[m] = "Freeway" or fcgroup[m] = "MLHighway" then do
				
				roadclass = "Major"
				
				// As soon as you determine that it's a major project, stop the loop.
				goto stopfccheck
				
			end
			
		end	
		
		stopfccheck:
		


		
		
		// Add up the secondary benefit around the project (but not on the project links themselves)


		if roadclass = "Major" then
		n2 = SelectByVicinity("LinkSelection", "Several", scenlLayer + "|Projects", buffer1, )
		
		if roadclass = "Minor" then
		n2 = SelectByVicinity("LinkSelection", "Several", scenlLayer + "|Projects", buffer2, )			
		

		
		secondaryquery = "Select * where UpdatedWithP<>'" + idarray[i] + "'"
		secondarynum = SelectByQuery("BufferAndNotProject", "Several", secondaryquery, {{"Source And", "LinkSelection"}})
		
		absecbenvec = GetDataVector(scenlLayer + "|BufferAndNotProject", "ABSecBen", {{"Sort Order",{{"ID","Ascending"}}},{"Missing as Zero", "True"}})
		basecbenvec = GetDataVector(scenlLayer + "|BufferAndNotProject", "BASecBen", {{"Sort Order",{{"ID","Ascending"}}},{"Missing as Zero", "True"}})
		
		for n = 1 to absecbenvec.length do
			
			surrsecbenchange = surrsecbenchange + absecbenvec[n] + basecbenvec[n]
			
		end
		
		//If the surrounding secondary benefit change is negative, just make it zero.
		surrsecbenchange = max(surrsecbenchange, 0)







		
		// Find other projects in the vicinity that also appear in the project ID list and add up the vmt on those links (only if it increases)


		
		
		// Create the subidarray that will be used in the next step to save time
		// It will only contain the projects that are within the buffer area, and are in the initial input ID list
		

		
		// This sub query will contain only the links within the buffer that have project IDs,
		// but will contain "junk" projects like "SpeedAdj" that are not in the MTP, and will contain duplicate IDs.
		
		subquery = "Select * where UpdatedWithP <> null "
		subidnum = SelectByQuery("Sub", "Several", subquery, {{"Source And", "LinkSelection"}})

		subidvec = GetDataVector(scenlLayer + "|Sub", "UpdatedWithP", {{"Sort Order",{{"UpdatedWithP","Descending"}}},{"Missing as Zero", "True"}})

		
		// Need to remove duplicates
		
		subidvec = SortVector(subidvec, {{"Unique", "True"}})
		
		
		// Convert the vector to an array to continue working with it
		
		tempsubidarray = VectorToArray(subidvec)
		
		
		// Need to remove "junk" project IDs
		
		dim subidarray[1]
		
		for a = 1 to tempsubidarray.length do
			
			pos = ArrayPosition(idarray, {tempsubidarray[a]},)
			
			if pos > 0 then subidarray = InsertArrayElements(subidarray, subidarray.length, {tempsubidarray[a]})
			
		end
		
		// When that process is finished, subidarray is left with a null in the last position.  Need to remove it.
		
		subidarray = ExcludeArrayElements(subidarray, subidarray.length, 1)

		
		
		
		
		

		for k = 1 to subidarray.length do

		// Select the links of project k that are within the buffer area for project i
		
		query2 = "Select * where UpdatedWithP='" + subidarray[k] + "'"
		n4 = SelectByQuery("KProj", "Several", query2, {{"Source And", "LinkSelection"}})


			
			
			if n4>0 then do		// now that the subidarray is being used, this is probably not needed - n4 will always be greater than 0
				
				othprojvmtdiff = 0																																		// This will hold the VMT difference for just this project [k]
				
				abvoldiff = GetDataVector(scenlLayer + "|KProj", "AB_Flow_Daily_diff", {{"Sort Order",{{"ID","Ascending"}}},{"Missing as Zero", "True"}})
				bavoldiff = GetDataVector(scenlLayer + "|KProj", "BA_Flow_Daily_diff", {{"Sort Order",{{"ID","Ascending"}}},{"Missing as Zero", "True"}})
				linklength = GetDataVector(scenlLayer + "|KProj", "Length", {{"Sort Order",{{"ID","Ascending"}}},{"Missing as Zero", "True"}})
				
				// For each project, add up the total VMT change.
				
				for l = 1 to abvoldiff.length do
					
					// As you loop through the list of projects (k), one of the loops will be for the actual project itself.
					// In that case, add it to the projvmtincr variable.  Otherwise, add it to the othprojvmtdiff variable.
					
					if subidarray[k] = idarray[i] then
					projvmtincr = projvmtincr + (abvoldiff[l] + bavoldiff[l])*linklength[l]
					else
					othprojvmtdiff = othprojvmtdiff + (abvoldiff[l] + bavoldiff[l])*linklength[l]
					
				end				
				
				// If the total projectcmt increase is negative, make it zero (it won't be credited with any secondary benefits)

				projvmtincr = max(projvmtincr, 0)
				
				
				// If the current, other-project's vmt change is negative, don't add it to the surrprojvmtincr variable
				// This will ensure that only projects with increasing VMT are competing for secondary benefits
				
				if othprojvmtdiff > 0 then
				surrprojvmtincr = surrprojvmtincr + othprojvmtdiff
				
			end
			
			
			
		end		
		
		
		
		// After all the projects in the vicinity have been found, then the projvmtincr and surrprojvmtincr
		// variables will be ready to calculate the percentvmt and benefit variable
		
		if projvmtincr = 0 then percentvmt = 0
		else percentvmt = projvmtincr / (projvmtincr + surrprojvmtincr)
		
		
		projsecbenefit = surrsecbenchange * percentvmt
		
		
		// Add the primary and secondary benefits for the total project benefit
		
		totalbenefit = projprimebenefit + projsecbenefit



		// if this is for the first project, write the column headings as well.  Otherwise, just fill in the variables
		
		if i = 1 then do
		
			WriteLine(file, "ProjID" + "*" + "Classification" + "*" + "Project VMT Increase" + "*" + "Surrounding Projects' Increasing VMT" + "*" + "PercentVMT" + "*" + "Surrounding Sec Benefit" + "*" + "Daily Primary Benefit" + "*" + "Daily Secondary Benefit" + "*" + "Daily Total Benefit")
			WriteLine(file, idarray[i] + "*" + roadclass + "*" + r2s(projvmtincr) + "*" + r2s(surrprojvmtincr) + "*" + r2s(percentvmt) + "*" + r2s(surrsecbenchange) + "*" + r2s(projprimebenefit) + "*" + r2s(projsecbenefit) + "*" + r2s(totalbenefit))
			
		end
		else WriteLine(file, idarray[i] + "*" + roadclass + "*" + r2s(projvmtincr) + "*" + r2s(surrprojvmtincr) + "*" + r2s(percentvmt) + "*" + r2s(surrsecbenchange) + "*" + r2s(projprimebenefit) + "*" + r2s(projsecbenefit) + "*" + r2s(totalbenefit))
	end
	
	
	else WriteLine(file, idarray[i] + "*Not in Scenario")

	
end
	

	

CloseFile(file)
CloseFile(listfile)














EndMacro