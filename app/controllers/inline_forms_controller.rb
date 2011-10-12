# == Generic controller for the inline_forms plugin.
# === Usage
# If you have an Example class, make an ExampleController
# that is a subclass of InlineFormsController
#  class ExampleController < InlineFormsController
#  end
# That's it! It'll work. But please read about the InlineForms::InlineFormsGenerator first!
#
# You can override the methods in your ExampleController
#  def index
#    @objects=@Klass.all
#  end
#
#
# @objects holds the objects (in this case Examples)
# and @Klass will be set to Example by the getKlass before filter.
# 
# === How it works
# The getKlass before_filter extracts the class and puts it in @Klass
#
# @Klass is used in the InlineFormsHelper
#
class InlineFormsController < ApplicationController
  before_filter :getKlass

  def self.cancan_enabled?
    begin
      ::Ability && true
    rescue NameError
      false
    end
  end

  def cancan_enabled?
    self.class.cancan_enabled?
  end

  def cancan_disabled?
    ! self.class.cancan_enabled?
  end

  helper_method :cancan_disabled?, :cancan_enabled?

  load_and_authorize_resource if cancan_enabled?

  include InlineFormsHelper

  # shows a list of all objects from class @Klass, using will_paginate
  #
  # The link to 'new' allows you to create a new record.
  #
  def index
    update_span = params[:update]
    @parent_class = params[:parent_class]
    @parent_id = params[:parent_id]
    @ul_needed = params[:ul_needed]
    @PER_PAGE = 5 unless @parent_class.nil?
    # if the parent_class is not nill, we are in associated list and we don't search there.
    # also, make sure the Model that you want to do a search on has a :name attribute. TODO
    @parent_class.nil? ? conditions = [ @Klass.order_by_clause.to_s + " like ?", "%#{params[:search]}%" ] : conditions =  [ "#{@parent_class.foreign_key} = ?", @parent_id ]
    if cancan_enabled?
      @objects = @Klass.accessible_by(current_ability).order(@Klass.order_by_clause).paginate :page => params[:page], :per_page => @PER_PAGE || 12, :conditions => conditions
    else
      @objects = @Klass.order(@Klass.order_by_clause).paginate :page => params[:page], :per_page => @PER_PAGE || 12, :conditions => conditions
    end
    respond_to do |format|
      format.html { render 'inline_forms/_list', :layout => 'inline_forms' } unless @Klass.not_accessible_through_html?
      format.js { }
    end
  end

  # :new prepares a new object, updates the entire list of objects and replaces it with a new
  # empty form. After pressing OK or Cancel, the list of objects is retrieved in the same way as :index
  #
  # GET /examples/new
  def new
    @object = @Klass.new
    @update_span = params[:update]
    @parent_class = params[:parent_class]
    unless @parent_class.nil?
      @parent_id = params[:parent_id]
      @object[@parent_class.foreign_key] = @parent_id
    end
    respond_to do |format|
      format.js { }
    end
  end

  # :edit presents a form to edit one specific attribute from an object
  #
  # GET /examples/1/edit
  #
  def edit
    @object = @Klass.find(params[:id])
    @attribute = params[:attribute]
    @form_element = params[:form_element]
    @sub_id = params[:sub_id]
    @update_span = params[:update]
    respond_to do |format|
      format.js { }
    end
  end

  # :create creates the object made with :new. It then presents the list of objects.
  #
  # POST /examples
  #
  def create
    object = @Klass.new
    @update_span = params[:update]
    attributes = object.inline_forms_attribute_list
    attributes.each do | attribute, name, form_element |
      send("#{form_element.to_s}_update", object, attribute) unless form_element == :associated
    end
    @parent_class = params[:parent_class]
    @parent_id = params[:parent_id]
    @PER_PAGE = 5 unless @parent_class.nil?
    # for the logic behind the :conditions see the #index method.
    @parent_class.nil? ? conditions = [ @Klass.order_by_clause.to_s + " like ?", "%#{params[:search]}%" ] : conditions =  [ "#{@parent_class.foreign_key} = ?", @parent_id ]
    object[@parent_class.foreign_key] = @parent_id unless @parent_class.nil?
    if object.save
      flash.now[:success] = "Successfully created #{object.class.to_s.underscore}."
      if cancan_enabled?
        @objects = @Klass.accessible_by(current_ability).order(@Klass.order_by_clause).paginate :page => params[:page], :per_page => @PER_PAGE || 12, :conditions => conditions
      else
        @objects = @Klass.order(@Klass.order_by_clause).paginate :page => params[:page], :per_page => @PER_PAGE || 12, :conditions => conditions
      end
      respond_to do |format|
        format.js { render :list }
      end
    else
      flash.now[:error] = "Failed to create #{object.class.to_s.underscore}.".html_safe
      object.errors.each do |e|
        flash.now[:error] << '<br />'.html_safe + e[0].to_s + ": " + e[1]
      end
      respond_to do |format|
        @object = object
        format.js { render :new}
      end
    end
  end
  # :update updates a specific attribute from an object.
  #
  # PUT /examples/1
  #
  def update
    @object = @Klass.find(params[:id])
    @attribute = params[:attribute]
    @form_element = params[:form_element]
    @sub_id = params[:sub_id]
    @update_span = params[:update]
    send("#{@form_element.to_s}_update", @object, @attribute)
    @object.save
    #puts "Requested #{request.format}"
    respond_to do |format|
      format.js { }
    end
  end

  # :show shows one attribute (attribute) from a record (object). It inludes the link to 'edit'
  #
  # GET /examples/1?attribute=name&form_element=text
  #
  
  def show
    @object = @Klass.find(params[:id])
    @attribute = params[:attribute]
    @form_element = params[:form_element]
    close = params[:close] || false
    if @form_element == "associated"
      @sub_id = params[:sub_id]
      if @sub_id.to_i > 0
        @associated_record_id = @object.send(@attribute.to_s.singularize + "_ids").index(@sub_id.to_i)
        @associated_record = @object.send(@attribute)[@associated_record_id]
      end
    end
    @update_span = params[:update]
    if @attribute.nil?
      respond_to do |format|
        @attributes = @object.inline_forms_attribute_list
        if close
          format.js { render :close }
        else
          format.js { }
        end
      end
    else
      respond_to do |format|
        format.js { render :show_element }
      end
    end
  end

  def destroy
    @update_span = params[:update]
    @object = @Klass.find(params[:id])
    @object.destroy
    respond_to do |format|
      format.js { render :show_undo }
    end
  end

  def revert
    # http://railscasts.com/episodes/255-undo-with-paper-trail
    @update_span = params[:update]
    @version = Version.find(params[:id])
    @version.reify.save!
    @object = @Klass.find(@version.item_id)
    respond_to do |format|
      format.js { render :close }
    end

    #    if @version.reify
    #      @version.reify.save!
    #    else
    #      @version.item.destroy
    #    end
    #    link_name = params[:redo] == "true" ? "undo" : "redo"
    #    link = view_context.link_to(link_name, revert_version_path(@version.next, :redo => !params[:redo]), :method => :post)
    #    redirect_to :back, :notice => "Undid #{@version.event}. #{link}"
  end

  private
  # Get the class from the controller name.
  def getKlass #:doc:
    @Klass = self.controller_name.classify.constantize
  end

end
