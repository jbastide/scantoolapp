
#
# Right now, there's no model in the application. We have a custom class that
# represents a scan tool. I'm going to write it this way, and then when it's working, 
# I can see about creating a model for our app and adding persistence of scan results.
#

class StaticPagesController < ApplicationController  
  def home
    @msg = "This is the static pages controller and I'm fucking around with it."
    
    #Looks like code for the home page goes here.
    @pdf_file = params[:pdf]
    @varer = params[:varer]
    @trans = params[:trans]
    
    
    
    #@varer_file
    #@trans_file
  end
  
  
  #
  # Let's see if we want to split up the upload into another controller action.
  # If we do, then the router needs to take the post data and send the user back to
  # index page to start. We want to ensure the files get uploaded.
  # UPDATE: Not using this action for now. All staying on the home page.
  
  def upload
    
    pdf = params[:pdf]
    varer = params[:varer]
    trans = params[:trans]
    
    # I'm building it within the upload action for now.
    
    
    # Get filehandles for files. Pass these in as parameters to the script. 
    
    @scanTool = ScanTool.new(pdf,varer,trans)
 
    @result = @scanTool.runAnalysis

    
  end
  
  #
  # We have upload buttons for the files in the views, but the actual action 
  # will be to analyze an order. To keep the semantics logical, we may end up 
  # changing the name of the 'upload' action above so it better matches
  # our actual action. This is just the 'naming things' challenge.
  #
  
  def processOrder
    
  end
  
 
  
end
