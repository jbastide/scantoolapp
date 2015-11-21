# TODO: Move dependencies into a gemspec and use bundler.
# encoding: utf-8
require 'ostruct'
require 'pp'
require 'pdf-reader'
require 'terminal-table/import'
require 'fuzzystringmatch'
require 'colorize'
require 'byebug'

EANMAPFILEPATH = "./varer.dat" #In this example, we have the varer.dat file in the
                               # same directory that we're running the tool.


#
# For now, we'll just require this from the model, 
# so I'll put it there to start.
#                              
                          
class ScanTool

  attr_accessor :pdf # Now we have automatic getter and setter 
                     # methods for these instance variables.
  attr_accessor :trans_files
  attr_accessor :varer
  
  #
  # Initialize a new ScanTool. Get the filehandles to the 
  # pdf, trans, and varer files.
  #
  
  def initialize(pdf, trans_files, varer)
    @pdf = pdf.to_io
    @trans = trans_files # Should be an array
    @varer = varer.to_io
  end
  
  #
  # Create a PDF reader object
  #

  def self.makeReader(file)
    reader = nil
  	reader = PDF::Reader.new(file)
    puts "Reader object: #{reader}"
    return reader
  end

  #
  # Don't fill the list with blank lines.
  # Better to just use a Ruby method that does the same thing.
  # I think readlines may do it, but need to check.
  #

  def self.verifyEntry(entry)
  	if entry == ""
  		return nil
  	else
  		return entry
  	end
  end

  #
  # Returns a list of items, grouped by page on the packing list. Each item list
  # is a newline separated string that needs further processing. Part of the
  # PDF parsing code.
  #

  def self.splitIntoSections(page)	
  	sublist = []

  	#
  	# Break this on newlines. A lot easier to parse.
  	# Returns a list.
  	#
	
  	splitPage = page.text.split(/\n/)	
	
  	#
  	# If you find the 'Artikel' line, set a boolean to gather matches until 
  	# you get to the next line which is only a newline.
  	#
	
  	match = false
	
  	splitPage.each do |entry|
  		if entry =~ (/Artikel/)
			
  			#
  			# Go to the next entry after the descriptor field and save each line
  			# until you get to the end of the data field.
  			#
			
  			match = true
			
  			# Reset the newline counter in case of spaces between Artikel and the first item.
  			#newlineCounter = 0
  			next
  		elsif entry =~ /Last/ or entry =~ /Utskriftstid/
  			match = false # Use that keyword match as the separator
  		elsif match == true # Only after all the checks are true do we push the data to the list.
  			verifiedEntry = ScanTool.verifyEntry(entry)
  			if verifiedEntry != nil
  				sublist << verifiedEntry
  			end
  		end
  	end
  	return sublist
  end

  #
  # Helper function.
  #

  def self.convertNumField(strEntry)
  	newEntry = strEntry.lstrip.chomp.split()
  	return newEntry[0].to_i
  end

  #
  # Alternative parser, to better get matches. Returns array of item properties.
  # [itemNum, itemDesc, itemQuant]
  # There's a bug whereby part of the order number can end up in the description field. 
  #

  def self.parseEntry(entry)
  	splitEntry = []
		
  	# Get the item number
  	itemNum = /^(\w+)\s+/.match(entry.lstrip.chomp)
  	splitEntry << itemNum[1]
	
    #
  	itemDescription = /^\w+\s+(.+)\d{4,6}/.match(entry.lstrip.chomp)
	
          # Convert match object to string.
  	itemDescription = itemDescription[1].encode("UTF-16be", :invalid=>:replace, :replace=>"?").encode('UTF-8').lstrip.rstrip
  #
    # Allowed the description field to capture the order number as well. This helps us avoid losing additional characters,
    # and the string matching still seems to work. Problem is that we're not detecting all duplicates this way.
    #
  
  	#itemDescription = /^\w+\s+(.+\d{4,6})/.match(entry.lstrip.chomp)
  
  	#splitEntry << itemDescription[1]
  	splitEntry << itemDescription

  	itemQuant = /\s{12,}(\d+).{,6}?$/.match(entry.lstrip.chomp)

  	itemQuantity = ScanTool.convertNumField(itemQuant[1])
  	splitEntry << itemQuantity
	
  	return splitEntry
  end

  #
  # Create a sorted list of Item numbers and descriptions based on the master list.
  #

  def self.generateSortedList(masterHashList)
  	# Create list of item numbers'
  	itemNumbers = []
	
  	masterHashList.each do |item|
  		itemNumbers << item[:itemNum] 
  	end
	
  	sortedItemNumbers = itemNumbers.sort
  	return sortedItemNumbers
  end

  #
  # Create a master list. Format is below in entryHash. List of hash properties for each item.
  # What I like about this approach is that the metadata of hash keys is clear. 
  #
  #

  def self.createMasterList(reader)
  	# Start by making a big list of item description strings.
  	masterStringList = []
  	masterHashList = []
	
  	reader.pages.each do |page|
  		section = ScanTool.splitIntoSections(page)
  		masterStringList.concat(section)
  	end
	
  	masterStringList.each do |entry|
  		# Here the entry is broken into list elements in its own array.
  		parsedEntry = ScanTool.parseEntry(entry)
  		entryHash = {:itemNum => parsedEntry[0],
  					 :itemDesc => parsedEntry[1],
  					 :itemQuant => parsedEntry[2],
  					:scannedQuantity => nil,
  					:scannedDescription => nil,
  					:scannedEAN => nil,
  					:scannedSerials => [],
  					:confidence => nil,
  					:descriptionFrequency => 0 # New field for detecting duplicates.
  					}					
  		masterHashList << entryHash
  	end
	
  	return masterHashList
  end

  #
  # One use-case we have is that the packing lists and inventory list on the computer
  # are not sorted the same. Nice to have them both share the same format. Makes it faster.
  # Update: Need to verify how computer sorts items. Default doesn't seem to be by item 
  # number.
  #

  def self.createSortedItemDescList(sortedList, masterHashList)
  	descList = []
	
  	masterHashList.each do |entry|
  		itemNumber = entry[:itemNum]
  		sortedList.each do |number|
  			if number == itemNumber
  				descList <<  [number,entry[:itemDesc],entry[:itemQuant]]
  				break
  			end
  		end
  	end

  	return descList.sort
  end

  #
  # As input, this takes a list of the form [["item number", "item description", item-quantity],]
  # Returns a table that's fit for display on the screen or ASCII printer output. This displays
  # the PDF packing list.
  #

  def self.viewSortedItemDescList(descList)
  	itemTotal = 0 # Total number of individual items in the order.
	
  	displayTable = table do
  		table.style = {:padding_left => 3, :padding_right => 3}
  		self.headings = "Item Number", "Item Description", "Item quantity"
		
  		descList.each do |entry|
  			add_row [entry[0], entry[1], entry[2]]
  			self.add_separator
  			itemTotal += entry[2]
  		end
		
  		add_row [{value: "Total number of individual items on packing list", colspan: 2}, itemTotal]
  		add_row [{value: "Total number of SKU entries on packing list:", colspan: 2}, descList.length]
  	end
  	puts displayTable
  	return displayTable	
  end

  #
  # As input, take a sorted item list and send it to a file.
  # TODO: Allow us to specify a filename.
  #

  def self.outputFileSortedTable(tabularItemList)
  	f = File.new("sortedPackingList.txt","w")
  	f.write(tabularItemList)
  end

  #
  # Returns a list of individual lines.
  #

  def self.processFile(fileHandle)
  	puts "Processing file."
	
  	begin
  		lineArray = fileHandle.readlines
  	rescue
  		puts "Unable to open file."
  	end
	
  	return lineArray
  end

  #
  # Transform the EAN data into a useful, hashed form.
  #

  def self.transformEanFile(itemIdDescList)
  	#
  	# Standard processing stuff. Chomp trailing spaces. Ignore blank lines.
  	# The numeric codes are thirteen characters, then the rest is the item 
  	# description.
  	#

  	hashedData = {}
	
  	itemIdDescList.each do |entry|
  		cleanEntry = entry.chomp
		
  		#
  		# Encoding hack. The data is tagged as UTF-8, but there are invalid byte sequences. I think
  		# there's some Norwegian in here. I'll have to look up the encoding for that. 
  		# This is a 'lossy' hack, in that we're converting to a different encoding than UTF-8 in order 
  		# to force ruby to replace invalid characters. Then we convert back to UTF-8.
  		# I'm willing to try this hack because the description matches will use 'fuzzy' matching
  		# instead of regular expressions.
  		#
	    # This encoding hack is broken in rails.
  		cleanEntry = cleanEntry.lstrip.rstrip	
  		#cleanEntry = cleanEntry.encode("UTF-16be", :invalid=>:replace, :replace=>"?").encode('UTF-8').lstrip.rstrip	
  		
      begin # TODO: Can't we un-nest the begin/rescue statement here? Would be good to test this. 
  			itemID = cleanEntry.match(/^(\d{13})/)[1]
  			begin
  				itemDescription = cleanEntry.match(/^\d{13}(.+)/)[1]
  			rescue Exception => ex
  				puts ex
  				puts "Can't parse description for EAN in varer.dat: #{itemID}"
  			end
  			hashedData[itemID] = itemDescription
  			#puts "DEBUG: Item description: #{itemDescription}"
  		rescue Exception => e
  			pp e
  			raise e
  		end
  	end
		
  	return hashedData
  end

  #
  # Transform the scanner data into a useful, hashed form.
  # Return a list of the form: [{itemEAN => {itemQuant: , itemSerial: }}]
  #

  def self.transformScannerData(scanDataList)
  	hashedData = {}

  	scanDataList.each do |entry|
  		serialNumbers = []
  		cleanEntry = entry.chomp()
		
  		itemEAN = cleanEntry.match(/(\w+)\s+/)[1] #TODO: Make this regex more strict.
		
  		#
  		# Assume serial numbers are longer than three digits.
  		#
		
  		itemQuantity = cleanEntry.match(/\s+(\w+)/)[1]   

  		#
  		# Now we start to get more strict with the item quantity to
  		# differentiate between item quantities and serial numbers.
  		# Assumes any given order has no more than 999 of any given item.
  		#
		
  		if itemQuantity.length > 4 or itemQuantity !~ /\d{1,4}$/
  			serialNumber = itemQuantity # If it´s a long number, assume a serial number.
  			# Allow up to 9999 individual items for a given SKU in an order.
  			serialNumbers << serialNumber 
  			itemQuantity = 1 # Items with serial numbers are always quantity = 1.
  		end
      itemQuantity = itemQuantity.to_i
		
      #	
  		# If item exists, do an update of the quantity field.
  		#

  		if hashedData[itemEAN]
        hashedData[itemEAN][:itemQuant] += itemQuantity
        # Update the serial numbers field.
        if hashedData[itemEAN][:serialNumbers]
          hashedData[itemEAN][:serialNumbers] << serialNumbers[0]
        end    
  		else 
  			# Otherwise create an entry.
  			hashedData[itemEAN] = {itemQuant: itemQuantity, :serialNumbers => serialNumbers}
  		end
  	end
	
  	return hashedData
  end

  #
  # This is where we combine the varer.dat file (EAN => Description) with the 
  # output from the scanner (EAN => Quantity | serial number).
  #

  def self.generateDescriptionQuantityMap(hashedScannerData, hashedEanFile)
  	descQuant = []	
  	hashedScannerData.keys.each do |itemID|
  		if hashedEanFile[itemID]
  			descQuant << {itemEAN: itemID,
          itemDescription: hashedEanFile[itemID], 
  				itemQuantity: hashedScannerData[itemID][:itemQuant],
  				itemSerials: hashedScannerData[itemID][:serialNumbers]}
  		end
  	end
	
  	return descQuant
  end

  #
  # Bread and butter method to get all the matches between the packing list data and
  # the scanned item data.
  # TODO: Make this even more useful by storing the top three or four matches and returning those
  # values. We could then display them in the final report if the match confidence was low. The
  # goal would be making it quick to identify matching items without having to do a lot of scrolling
  # up and down on the screen.
  #

  def self.getAllMatches(descQuant, masterHashList)
    itemsMatched = []
  	match = nil
  	jarow = FuzzyStringMatch::JaroWinkler.create( :native )

  	masterHashList.each do |expectedItem|
  		jaroDistanceHash = {} # All results for a given entry in the master hash
  		descQuant.each do |scannedItem|
  			d = jarow.getDistance( scannedItem[:itemDescription].downcase, expectedItem[:itemDesc].downcase)
  			jaroDistanceHash[d] = {scannedItem: scannedItem, expectedItem: expectedItem}
  		end

  		#		
  		# Sort keys in descending order. This puts the greatest Jarrow match value first in the array.
  		#

  		sortedKeys = jaroDistanceHash.keys.sort{|x,y| y <=> x}
    
  		#		
  		# Store the best match in the form {scannedItem: scannedItem, expectedItem: expectedItem}
  		#

  		bestMatch = jaroDistanceHash[sortedKeys[0]]
    			
  		#	
  		# This gives us the best match in a set if the Jarrow distance is over 0.92
  		#
    
      if sortedKeys[0] > 0.92
		
        #
        # Update Master Hash List with: scannedQuantity, scannedDescription, confidence.
        #
      
        expectedItem[:scannedQuantity] = bestMatch[:scannedItem][:itemQuantity]   
        expectedItem[:scannedDescription] = bestMatch[:scannedItem][:itemDescription]
        expectedItem[:scannedEAN] = bestMatch[:scannedItem][:itemEAN]
        expectedItem[:scannedSerials] = bestMatch[:scannedItem][:itemSerials]
        expectedItem[:confidence] = sortedKeys[0]
			
  		end
  	end

  	return masterHashList
  end


  def self.calculateTotalItemsScanned(combinedData)
  	scannedTotal = 0

  	combinedData.each do |entry|
  		if entry[:scannedQuantity]
  			scannedTotal += entry[:scannedQuantity]
  		end 
  	end
	
  	return scannedTotal
  end


  #
  # Helper to color code description frequencies.
  # Any description that appears more than once on the packing list
  # will require double checking the item quantity, since it's 
  # a duplicate and will throw off the matching algorithm.
  #

  def self.descFreqColorCheck(entry)
  	frequency = entry[:descriptionFrequency]
	
  	if frequency > 1
  		coloredEntry = frequency.to_s.red
  	end
	
    return coloredEntry
  end

  #
  # Helper to color code results based on match confidence.
  #

  def self.confidenceColorCheck(entry)
  	confidence = entry[:confidence]

  	if confidence == nil
  		confidence = 0
  	end

  	if confidence >= 0.95
  		coloredEntry = confidence.round(3).to_s.green
  	elsif confidence >= 0.92 and confidence < 0.95
  		coloredEntry = confidence.round(3).to_s.yellow
  	elsif confidence > 0.80 and confidence < 0.92
  		coloredEntry = confidence.round(3).to_s.magenta
  	else
  		coloredEntry = confidence.round(3).to_s.red
  	end

  	return coloredEntry
  end

  #
  # Look for duplicate descriptions
  #

  def self.duplicateDescriptionUpdate(combinedData)
    #	
  	# Items that have duplicate descriptions should be flagged for manual follow-up.
  	# N^2 sized comparison. 
    #

  	combinedData.each do |entry|
  		combinedData.each do |record|
  			if entry[:itemDesc] == record[:itemDesc]
  				entry[:descriptionFrequency] += 1
  			end
      
        #
        # Check if the scanned descriptions are dupes as well. Make sure
  			# we're not comparing nil values.
        #
                       
  			if entry[:itemDescription] and entry[:itemDescription] == record[:itemDescription]
          puts entry[:itemDescription]
  				puts record [:itemDescription]
  				entry[:descriptionFrequency] += 1
        end
  		end
    
  	  #
      # Items that have :descriptionFrequency > 1 need to unset the scanned
      # EAN and scanned quantities, since these could be wrong. This is an
      # unfortunate consequence of matching items using description strings. If 
      # we had unique article numbers or EANs across our data sources, we wouldn't 
      # have this issue. The workaround will be for the tool to output multiple suggestions
      # for items that have duplicate descriptions.
      #
    
      if entry[:descriptionFrequency] > 1
        entry[:scannedQuantity] = nil
        entry[:scannedEAN] = nil
      end
    end
  
    return combinedData
  end

  #
  # Data visualization. Table of items, including expected and scanned quantities.
  #

  def self.showCombinedData(combinedData)

  	totalItemsScanned = ScanTool.calculateTotalItemsScanned(combinedData)
    combinedData = combinedData.sort_by {|k| k[:itemDesc].downcase}
  
  	displayTable = table do 
  		self.headings = "SKU", "EAN", "Description", "Matched Description", "Expected_Quant", 
  "Scanned_Quant", "Confidence", "Desc Freq"
	
      combinedData.each do |entry|
        colorCodedFrequency = ScanTool.descFreqColorCheck(entry)
  		  colorCodedConfidence = ScanTool.confidenceColorCheck(entry)
  		  add_row [ entry[:itemNum], entry[:scannedEAN],
  	      entry[:itemDesc], entry[:scannedDescription], 
  	      entry[:itemQuant], entry[:scannedQuantity], colorCodedConfidence, colorCodedFrequency ]
  		  self.add_separator
  	  end
		
      add_row [{value: "Total number of scanned items", colspan: 1}, totalItemsScanned]
    end
	
    #
    # This is where we show the ASCII table of results.
    #
  
  	puts displayTable
  	return displayTable, combinedData
  end



  def self.makeUniqMasterHash(masterHashList)
  
    #
    # Transform the existing list to make it unique with updated item quantities.
    # 
  
    uniqMasterHashList = []
  
    #
    # Make a blank list to hold uniq hash item numbers. We can sort these.
    #
  
    itemNumsUniqSorted = []
  
    #
    # Iterate through the hash items and create a list of item numbers.
    # Sort the list. This will be the item order. Make the list only hold
    # unique items.
    #
  
    masterHashList.each do |item|
      itemNumsUniqSorted << item[:itemNum]
    end
    itemNumsUniqSorted = itemNumsUniqSorted.uniq.sort()
  
  
    itemNumsUniqSorted.each do |num|
    
      # 
      # This is a list of all items in the masterHashList that match a given uniq item number.
      #
    
      occurences = masterHashList.find_all {|m| m[:itemNum] == num} 
    
      #
      # Start our count from zero until we tell it otherwise.
      #
    
      itemTotal = 0
    
      #
      # Update total number of items for a given SKU. 
      #
    
      occurences.each do |instance|
        itemTotal += instance[:itemQuant]
      end
    
      #
      # Since all the instances in occurences are the same type of item
      # (with the same article number,) then just take the first occurence in
      # the list and change the quantity to the total number of items counted. 
      #
    
      occurences[0][:itemQuant] = itemTotal
      uniqMasterHashList << occurences[0]
    end

    total = 0
    totalItemsExpected = uniqMasterHashList.each do |i|
      total += i[:itemQuant]
    end
  
    puts "INFO: Total unique items expected after consolidating duplicate SKUs: #{total}"
    puts "INFO: Total unique SKUs expected after consolidation: #{uniqMasterHashList.length} "
  
    return uniqMasterHashList 
  end


  #
  # Look for results that appear in the scanner data but weren't matched.
  # 
  # Remember: descQuant << {itemEAN: itemID,
  #						itemDescription: hashedEanFile[itemID], 
  #						itemQuantity: hashedScannerData[itemID][:itemQuant],
  #						itemSerials: hashedScannerData[itemID][:serialNumbers]}
  #

  def self.findUnmatchedResults(descQuant, uniqHashList)
  
    matched = []
    notMatched = []
    sortedNotmatched = []

    matched = uniqHashList.find_all {|i| i[:scannedEAN] != nil}
    descQuant.each do |scanned|
      if matched.find { |i| i[:scannedEAN] == scanned[:itemEAN] }
      else
        notMatched << scanned
      end
    end

    sorted = notMatched.sort_by {|k| k[:itemDescription].downcase} 
  
    puts "WARN: The following items were scanned but could not be \
  reliably matched against the packing list using description strings."
    puts "***"
  
  
  	displayTable = table do 
  		self.headings = "Description", "Quantity", "EAN"
	
      sorted.each do |entry|
  		  add_row [ entry[:itemDescription], entry[:itemQuantity],
  	      entry[:itemEAN] ]
  		  self.add_separator
      end
    end
  
    puts displayTable
  end

  def self.displayAllScanned(descQuant)
    sorted = []
    sorted = descQuant.sort_by {|k| k[:itemDescription].downcase}
    sorted.each do |scanned|
      puts "####"
      puts scanned
    end
  end
  
  #
  # This is where we invoke all the methods to run the analysis. Similar to the main()
  # method.
  #
  
  def runAnalysis
    scanDataFileHandles = @trans #This is an array of uploaded files
    scanDataList = nil
    hashedScannerData = {}
    eanFileHandle = @varer.to_io
    eanMapList = nil
    hashedEanFile = {}
    descQuant = [] # EANs, descriptions, and scanned quantities. Used when we
    			         # match items in the packing list.
    tabularItemList = []
    
  	
	  reader = ScanTool.makeReader(@pdf)
    puts "DEBUG: Reader: #{reader}"
		if reader
			puts "Created reader object from packing list."
    else
      exit(1)
    end
  
    
  	masterHashList = ScanTool.createMasterList(reader)
  	sortedItemNumList = ScanTool.generateSortedList(masterHashList)
  	nestedItemList = ScanTool.createSortedItemDescList(sortedItemNumList, masterHashList)
  	
    #
    # For now, we'll write all this to the console. Later, we'll just return data
    # structures and figure out a nice way to present it in rails. So this presentation
    # code will get taken out.
    #
    
    tabularItemList = ScanTool.viewSortedItemDescList(nestedItemList)
    
  	begin
  		puts "INFO: Processing EAN mapping file." # This is varer.dat
  		masterEanMapList = []                    
  		eanMapList = ScanTool.processFile(@varer)
      masterEanMapList.concat(eanMapList) # Make the master list one big list. That's why we use concat.
                                          # We may not even need this, because varer.dat is always a single file.
                                          # Could do: masterEanMapList = processFile(@varer)
      hashedEanFile = ScanTool.transformEanFile(masterEanMapList)
    
  	rescue Exception => e
  		puts "Unable to process EAN mapping file"
  		raise e
  		exit
  	end
    
  	begin
  		puts "INFO: Processing scan data file."
  		masterScanDataList = []
      scanDataFileHandles.each do |file|
  		  scanDataList = ScanTool.processFile(file.to_io)
        masterScanDataList.concat(scanDataList)
      end
  		hashedScannerData = ScanTool.transformScannerData(masterScanDataList)
  	rescue
  		puts "ERROR: Unable to process scan data file."
  	end
    

    descQuant = ScanTool.generateDescriptionQuantityMap(hashedScannerData, hashedEanFile)
    
    #
    # Need to make the master hash list sorted by SKU as well as containing only
    # unique items.
    #

    uniqHashList = ScanTool.makeUniqMasterHash(masterHashList)
    
    
  	#	
  	# Match scanned output with packing list data to make a list of items received.
  	# Be prepared for there to be items with different EANs but the same description.
  	#
    #byebug
  	combinedData = ScanTool.getAllMatches(descQuant, uniqHashList)
  
    #
    # Transform the combined scanner and packing list data, adding in values for 
    # description frequency. If we find a value for description frequency > 1,
    # clear the scanned EAN as well as scanned quantities. This allows us to better
    # flag a dubious result and prevents us from displaying false EAN data for items
    # that match on a duplicate description.
    #
  
    combinedData = ScanTool.duplicateDescriptionUpdate(combinedData)
	
  	# Take the combined data and display it in a nice table.
    
  	ScanTool.showCombinedData(combinedData)

    #
  	# Show all scanned items. Use this as a reference for now. 
    # Later, this can be part of the verbose output, or another option. 
    # We shouldn't need to refer to the list of all scanned items when we display
    # addiitonal matches in the final report.
    #

    puts "All scanned results for matching against holes in matched list"
    ScanTool.displayAllScanned(descQuant)
  end
end



