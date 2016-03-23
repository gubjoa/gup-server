require 'pp'

class V1::PublicationsController < V1::V1Controller
  include PublicationsControllerHelper

  before_filter :find_current_person

  api :GET, '/publications', 'Returns a list of publications based on parameters'
  param :list_type, ['drafts', 'is_actor', 'is_actor_for_review', 'is_registrator', 'for_biblreview', 'delayed'], :desc => "drafts: Returns all drafts for current user. is_actor: Limits search to publications where current user is tied to the publication. for_review: Returns publications where the current user is actor and has not reviewed the current version of the publication. is_registrator: Limits search to publications where current user has created or updated the publication. for_biblreview: Returns all publications that has to be bibliographically reviewed. delayed: Returns all publications that are delayed for bibliographic review."
  description "Returns a list of publications, based on parameters and current user." 
  def index
    publications = publications_for_filter(list_type: params[:list_type])
    @response[:publications] = publications
    render_json(200)
  end

  api :GET, '/publications/:pubid', 'Returns a single publication based on pubid.'
  description "Returns a single complete publication object based on pubid. The most recent version of the publication is the one returned."
  def show
    pubid = params[:pubid]
    publication = Publication.where(pubid: pubid).where(is_deleted: false).first
    if publication.present? && publication.published_at.nil?
        if !publication.created_by.eql?(@current_user.username)
            publication = nil
        end
    end
    if publication.present?
      @response[:publication] = publication.as_json
      @response[:publication][:authors] = people_for_publication(publication_db_id: publication.id)
      authors_from_import = []
      if @response[:publication][:authors].empty? && publication.xml.present? && !publication.xml.nil?
        # Do the authorstring
        xml = Nokogiri::XML(publication.xml).remove_namespaces!
        datasource = publication.datasource
        if datasource.nil?
          # Do nothing
        elsif datasource.eql?("gupea")
          authors_from_import += Gupea.authors(xml)
        elsif  datasource.eql?("pubmed")
          authors_from_import += Pubmed.authors(xml)
        elsif  datasource.eql?("scopus")
          authors_from_import += Scopus.authors(xml)
        elsif  datasource.eql?("scigloo")
          authors_from_import += Scigloo.authors(xml)
        elsif  datasource.eql?("libris")
          authors_from_import += Libris.authors(xml)
        end
      end
      if publication.publication_type.blank? && publication.xml.present? && !publication.xml.nil?
        # Do the authorstring
        xml = Nokogiri::XML(publication.xml).remove_namespaces!
        datasource = publication.datasource
        if datasource.nil?
          # Do nothing
        elsif datasource.eql?("gupea")
          publication_type_suggestion = Gupea.publication_type_suggestion(xml)
        elsif  datasource.eql?("pubmed")
          publication_type_suggestion = Pubmed.publication_type_suggestion(xml)
        elsif  datasource.eql?("scopus")
          publication_type_suggestion = Scopus.publication_type_suggestion(xml)
        elsif  datasource.eql?("scigloo")
          publication_type_suggestion = Scigloo.publication_type_suggestion(xml)
        elsif  datasource.eql?("libris")
          publication_type_suggestion = Libris.publication_type_suggestion(xml)
        end
      end
      @response[:publication][:authors_from_import] = authors_from_import
      @response[:publication][:publication_type_suggestion] = publication_type_suggestion
    else
      error_msg(ErrorCodes::OBJECT_ERROR, "#{I18n.t "publications.errors.not_found"}: #{params[:pubid]}")
    end
    render_json
  end

  api :POST, '/publications', 'Creates a new publication, and returns the created object including pubid (as id)'
  def create
    params[:publication] = {} if !params[:publication]

    params[:publication][:created_by] = @current_user.username
    params[:publication][:updated_by] = @current_user.username
    
    if params[:publication][:xml] 
      params[:publication][:xml] = params[:publication][:xml].strip
    end

    error = false
    create_basic_data
    Publication.transaction do
      pub = Publication.new(permitted_params(params))
      if pub.save
        @response[:publication] = pub.as_json
      else
        error = true
        error_msg(ErrorCodes::VALIDATION_ERROR, "#{I18n.t "publications.errors.create_error"}", pub.errors)
        render_json
        raise ActiveRecord::Rollback
      end
      create_publication_identifiers(pub)
    end
    render_json(201) unless error.present?
  end



  api :GET, '/publications/fetch_import_data', 'Returns a non persisted publication object based on data imported from a given data source.'
  param :datasource, ['pubmed', 'gupea', 'scopus', 'libris', 'scigloo'], :desc => 'Declares which data source should be used to import data from.', :required => true
  param :sourceid, String, :desc => 'The identifier used to import publication data from given data source.', :required => true
  desc "Returns a non persisted publicatio object based on data imported from a given data source. Does not contain pubid or database id."
  def fetch_import_data
    datasource = params[:datasource]
    sourceid = params[:sourceid]
    params[:publication] = {}

    case datasource
    when "none"
      #do nothing
    when "pubmed"
      pubmed = Pubmed.find_by_id(params[:sourceid])
      if pubmed && pubmed.errors.messages.empty?
        pubmed.datasource = datasource
        pubmed.sourceid = sourceid
        params[:publication].merge!(pubmed.as_json)
      else
        error_msg(ErrorCodes::VALIDATION_ERROR, "Identifikatorn #{params[:sourceid]} hittades inte i Pubmed.")
        render_json
        return
      end
    when "gupea"
      gupea = Gupea.find_by_id(params[:sourceid])
      if gupea && gupea.errors.messages.empty?
        gupea.datasource = datasource
        gupea.sourceid = sourceid
        params[:publication].merge!(gupea.as_json)
      else
        error_msg(ErrorCodes::VALIDATION_ERROR, "Identifikatorn #{params[:sourceid]} hittades inte i Gupea")
        render_json
        return
      end
    when "libris"
      libris = Libris.find_by_id(params[:sourceid])
      if libris && libris.errors.messages.empty?
        libris.datasource = datasource
        libris.sourceid = sourceid
        params[:publication].merge!(libris.as_json)
      else
        error_msg(ErrorCodes::VALIDATION_ERROR, "Identifikatorn #{params[:sourceid]} hittades inte i Libris")
        render_json
        return
      end
    when "scopus"
      scopus = Scopus.find_by_id(params[:sourceid])
      if scopus && scopus.errors.messages.empty?
        scopus.datasource = datasource
        scopus.sourceid = sourceid
        params[:publication].merge!(scopus.as_json)
      else
        error_msg(ErrorCodes::VALIDATION_ERROR, "Identifikatorn #{params[:sourceid]} hittades inte i Scopus")
        render_json
        return
      end
    when "scigloo"
      scigloo = Scigloo.find_by_id(params[:sourceid])
      if scigloo && scigloo.errors.messages.empty?
        scigloo.datasource = datasource
        scigloo.sourceid = sourceid
        params[:publication].merge!(scigloo.as_json)
      else
        error_msg(ErrorCodes::VALIDATION_ERROR, "Identifikatorn #{params[:sourceid]} hittades inte i Scigloo")
        render_json
        return
      end
    else
      error_msg(ErrorCodes::OBJECT_ERROR, "Given datasource is not configured: #{params[:datasource]}")
    end

    # Check publication identifiers for possible duplications
    publication_identifiers = params[:publication][:publication_identifiers]
    publication_identifier_duplicates = []
    
    publication_identifiers.each do |publication_identifier|
      duplicates = PublicationIdentifier.where(identifier_code: publication_identifier['identifier_code'], identifier_value: publication_identifier['identifier_value']).pluck(:publication_id)
      duplicate_publications = Publication.where(id: duplicates).where(is_deleted: false).where.not(published_at: nil)
      duplicate_publications.each do |duplicate_publication|
        duplication_object = {
          identifier_code: publication_identifier['identifier_code'],
          identifier_value: publication_identifier['identifier_value'],
          publication_id: duplicate_publication.pubid,
          publication_title: duplicate_publication.title
        }
        publication_identifier_duplicates << duplication_object
      end
    end

    params[:publication][:publication_identifier_duplicates] = publication_identifier_duplicates

    @response[:publication] = params[:publication]
    render_json

  end

  api :PUT, '/publications/:pubid', 'Updates any value of a publication object'
  desc "Used for updating a publication object which is not yet published (draft). For published publications, the 'publish' endpoint is used."
  def update
    pubid = params[:pubid]
    publication_old = Publication.where(is_deleted: false).find_by_pubid(pubid)
    if publication_old
      params[:publication] = publication_old.attributes_indifferent.merge(params[:publication])
      params[:publication][:updated_by] = @current_user.username

      Publication.transaction do
        if !params[:publication][:publication_type]
          publication_new = Publication.new(permitted_params(params))
        else
          publication_type = PublicationType.find_by_code(params[:publication][:publication_type])
          if publication_type.present?
            publication_new = Publication.new(publication_type.permitted_params(params, global_params))
          else
            error_msg(ErrorCodes::VALIDATION_ERROR, "#{I18n.t "publications.errors.unknown_publication_type"}: #{params[:publication][:publication_type]}")
            render_json
            raise ActiveRecord::Rollback
          end
        end
        publication_new.new_authors = params[:publication][:authors]
          if publication_old.update_attribute(:is_deleted, true) && publication_new.save
          if params[:publication][:authors].present?
            params[:publication][:authors].each_with_index do |author, index|
              create_affiliation(publication_id: publication_new.id, person: author, position: index+1)
            end
          end
          #if !params[:publication][:publication_identifiers]
          #  publication_identifiers = PublicationIdentifier.where(publication_id: publication_old.id).all.map(&:as_json)
          #else
          #  publication_identifiers = params[:publication][:publication_identifiers]
          #end
          #publication_identifiers.each do |publication_identifier|
          #  publication_identifier[:publication_id] = publication_new.id
          #  publication_identifier
          #  PublicationIdentifier.create(publication_identifier.except('id'))
          #end

          @response[:publication] = publication_new.as_json
          @response[:publication][:authors] = people_for_publication(publication_db_id: publication_new.id)
          
          create_publication_identifiers(publication_new)

          render_json(200)
        else
          error_msg(ErrorCodes::VALIDATION_ERROR, "#{I18n.t "publications.errors.update_error"}", publication_new.errors)
          render_json
          raise ActiveRecord::Rollback
        end
      end
    else
      error_msg(ErrorCodes::OBJECT_ERROR, "#{I18n.t "publications.errors.not_found"}: #{params[:pubid]}")
      render_json
    end
  end

  api :PUT, '/publications/publish/:pubid', 'Updates any value of a publication object, including publishing it'
  desc 'Used for publishing a publication, as well as updating an already published publication. Also updates actor review states.'
  def publish
    pubid = params[:pubid]
    publication_old = Publication.where(is_deleted: false).find_by_pubid(pubid)
    published_at = DateTime.now
    if publication_old
      if publication_old.published_at
        published_at = publication_old.published_at
        #  # It is not possible to publish an already published publication
        #  error_msg(ErrorCodes::VALIDATION_ERROR, "#{I18n.t "publications.errors.already_published"}: #{params[:pubid]}")
        #  render_json
        #  return
      end
      params[:publication] = publication_old.attributes_indifferent.merge(params[:publication])
      params[:publication][:updated_by] = @current_user.username
      
      # Reset the bibl review info
      params[:publication][:biblreviewed_at] = nil
      params[:publication][:biblreviewed_by] = nil
      params[:publication][:bibl_review_start_time] = DateTime.now
      params[:publication][:bibl_review_delay_comment] = nil

      Publication.transaction do
        if !params[:publication][:publication_type]
          publication_new = Publication.new(permitted_params(params))
        else
          publication_type = PublicationType.find_by_code(params[:publication][:publication_type])
          if publication_type.present?
            publication_new = Publication.new(publication_type.permitted_params(params, global_params))
          else
            error_msg(ErrorCodes::VALIDATION_ERROR, "#{I18n.t "publications.errors.unknown_publication_type"}: #{params[:publication][:publication_type]}")
            render_json
            raise ActiveRecord::Rollback
          end
        end
        if !publication_new.published_at
          publication_new.published_at = published_at
        end
        publication_new.new_authors = params[:publication][:authors]

        if publication_old.update_attribute(:is_deleted, true) && publication_new.save
          if params[:publication][:authors].present?
            params[:publication][:authors].each_with_index do |author, index|
              oldp2p = People2publication.where(person_id: author[:id], publication_id: publication_old.id).first
              new_reviewed_at = nil
              new_reviewed_publication_id = publication_new.id
              if oldp2p
                new_reviewed_at = oldp2p.reviewed_at

                reviewed_p2p = nil
                # If last review date is nil and review has occured before, set review date to previous review date.
                if oldp2p.reviewed_at.nil? && oldp2p.reviewed_publication_id.present?
                  reviewed_p2p = People2publication.where(person_id: author[:id], publication_id: oldp2p.reviewed_publication_id).first
                  new_reviewed_at = reviewed_p2p.reviewed_at
                end
                new_reviewed_publication_id = oldp2p.reviewed_publication_id
                if oldp2p.reviewed_publication_id.present?
                  # Check if publication object is different
                  if publication_new.review_diff(oldp2p.reviewed_publication).present?
                    new_reviewed_at = nil
                  end

                  # Use revewd_p2p if it exists, otherwise use oldp2p for comparison
                  p2p_to_compare_with = oldp2p
                  if reviewed_p2p.present?
                    p2p_to_compare_with = reviewed_p2p
                  end

                  # Check if affiliations are different
                  if p2p_to_compare_with.departments2people2publications.blank? || author[:departments].blank?
                    new_reviewed_at = nil
                  else
                    old_affiliations = p2p_to_compare_with.departments2people2publications.map {|x| x.department_id}
                    new_affiliations = author[:departments].map {|x| x[:id].to_i}
                    unless (old_affiliations & new_affiliations == old_affiliations) && (new_affiliations & old_affiliations == new_affiliations)
                      new_reviewed_at = nil
                    end
                  end
                end
              end
            create_affiliation(publication_id: publication_new.id, person: author, position: index+1, reviewed_at: new_reviewed_at, reviewed_publication_id: new_reviewed_publication_id)
            end
          end


          @response[:publication] = publication_new.as_json
          @response[:publication][:authors] = people_for_publication(publication_db_id: publication_new.id)
          
          create_publication_identifiers(publication_new)
          
          render_json(200)
        else
          error_msg(ErrorCodes::VALIDATION_ERROR, "#{I18n.t "publications.errors.publish_error"}", publication_new.errors)
          render_json
          raise ActiveRecord::Rollback
        end
      end
    else
      error_msg(ErrorCodes::OBJECT_ERROR, "#{I18n.t "publications.errors.not_found"}: #{params[:pubid]}")
      render_json
    end
  end


  api :DELETE, '/publications/:pubid'
  desc 'Deletes a given publication based on pubid. Only effective on draft publications.'
  def destroy 
    pubid = params[:pubid]
    publication = Publication.where(is_deleted: false).find_by_pubid(pubid)
    if !publication.present?
      error_msg(ErrorCodes::OBJECT_ERROR, "#{I18n.t "publications.errors.not_found"}: #{params[:pubid]}")
      render_json
      return
    end
    if publication.published_at && !@current_user.has_right?('delete_published')
      error_msg(ErrorCodes::PERMISSION_ERROR, "#{I18n.t "publications.errors.cannot_delete_published"}")
      render_json
      return
    end
    if publication.update_attribute(:is_deleted, true)
      render_json
    else
      error_msg(ErrorCodes::VALIDATION_ERROR,"#{I18n.t "publications.errors.delete_error"}: #{params[:pubid]}")
      render_json    
    end

  end

  api :GET, '/publications/bibl_review/:pubid'
  desc 'Sets a specific publication version as bibliographically approved.' 
  def bibl_review
    if !@current_user.has_right?('bibreview')
      error_msg(ErrorCodes::PERMISSION_ERROR, "#{I18n.t "publications.errors.cannot_review_bibl"}")
      render_json
      return
    end

    pubid = params[:pubid]
    publication = Publication.where(pubid: pubid).where(is_deleted: false).first

    if !publication.present?
      error_msg(ErrorCodes::OBJECT_ERROR, "#{I18n.t "publications.errors.not_found"}: #{params[:pubid]}")
      render_json
      return
    end

    if publication.published_at.nil?
      error_msg(ErrorCodes::OBJECT_ERROR, "#{I18n.t "publications.errors.cannot_review_bibl"}")
      render_json
      return
    end

    if publication.update_attributes(biblreviewed_at: DateTime.now, biblreviewed_by: @current_user.username, epub_ahead_of_print: nil)
      @response[:publication] = publication
      render_json
    else
      error_msg(ErrorCodes::VALIDATION_ERROR, "#{I18n.t "publications.errors.cannot_review_bibl"}")
      render_json
    end
  end

  api :GET, '/publications/set_bibl_review_start_time/:pubid'
  param :date, String, :desc => 'The date for when a publication is ready for bibliographically review.', :required => true
  param :comment, String, :desc => 'Delay reason comment.', :required => false
  desc 'Sets a new start time for when a publication is ready for bibliographically review.' 
  def set_bibl_review_start_time
    if !@current_user.has_right?('bibreview')
      error_msg(ErrorCodes::PERMISSION_ERROR, "#{I18n.t "publications.errors.cannot_delay_bibl_review_time"}")
      render_json
      return
    end

    pubid = params[:pubid]
    publication = Publication.where(pubid: pubid).where(is_deleted: false).first

    if !publication.present?
      error_msg(ErrorCodes::OBJECT_ERROR, "#{I18n.t "publications.errors.not_found"}: #{params[:pubid]}")
      render_json
      return
    end

    if publication.published_at.nil?
      error_msg(ErrorCodes::OBJECT_ERROR, "#{I18n.t "publications.errors.cannot_delay_bibl_review_time"}")
      render_json
      return
    end
    
    if params[:date].blank? || !is_date_valid?(params[:date])
      error_msg(ErrorCodes::VALIDATION_ERROR, "#{I18n.t "publications.errors.cannot_delay_bibl_review_time_param_error"}: #{params[:pubid]}")
      render_json
      return      
    end

    extra_params = {}
    # If comment is epub ahead of print, set specific flag
    if params[:comment] == "E-pub ahead of print"
      extra_params[:epub_ahead_of_print] = DateTime.now
    end

    if publication.update_attributes({bibl_review_start_time: Time.parse(params[:date]), bibl_review_delay_comment: params[:comment]}.merge(extra_params))
      @response[:publication] = publication
      render_json
    else
      error_msg(ErrorCodes::VALIDATION_ERROR, "#{I18n.t "publications.errors.cannot_delay_bibl_review_time"}")
      render_json
    end  

  end



  api :GET, '/publications/review/:id'
  desc 'Sets a specific publication version as reviewed for the current user.'
  def review
    publication_id = params[:id]
    if !@current_person
      error_msg(ErrorCodes::OBJECT_ERROR, "#{I18n.t "publications.person_not_found"}")
      render_json
      return
    end

    # Find applicable p2p object
    people2publication = People2publication.where(person_id: @current_person_id).where(publication_id: publication_id).first

    if !people2publication
      error_msg(ErrorCodes::OBJECT_ERROR, "No affiliation found for publication")
      render_json
      return
    end

    if people2publication.publication.nil? || people2publication.publication.is_deleted || people2publication.publication.published_at.nil?
      error_msg(ErrorCodes::OBJECT_ERROR, "Publication is not in a reviewable state")
      render_json
      return
    end

    people2publication.update_attributes(reviewed_at: DateTime.now, reviewed_publication_id: publication_id)

    if people2publication.save!
      @response[:publication] = {}
      @response[:publication][:msg] = "Review succesful!"
      render_json
    else
      error_msg(ErrorCodes::VALIDATION_ERROR, "Could not review object")
      render_json
    end

  end

  def feedback_email 
    if !params.has_key?(:from) || !params.has_key?(:message) || !params.has_key?(:publication_id) 
      error_msg(ErrorCodes::REQUEST_ERROR, "Missing parameters") 
      render_json 
      return 
    end 
    params[:from] = @current_user.username
    if PublicationMailer.feedback_email(message: params[:message], publication_id: params[:publication_id], from: params[:from]).deliver_now 
      @response[:publication] = {}
      @response[:publication][:status] = "ok" 
      render_json
    else
      error_msg(ErrorCodes::OBJECT_ERROR, "Could not send email")
      render_json
    end
  end

  private

  def publication_identifier_permitted_params(params)
    params.require(:publication_identifier).permit(:publication_id, :identifier_code, :identifier_value)
  end

  def create_publication_identifiers(publication)
    if params[:publication][:publication_identifiers]
      pis_errors = []
      pis = []
      params[:publication][:publication_identifiers].each do |publication_identifier|
        publication_identifier[:publication_id] = publication.id
        pi = PublicationIdentifier.new(publication_identifier_permitted_params(ActionController::Parameters.new(publication_identifier: publication_identifier)))
        if pi.save
          pis << pi.as_json
        else
          pis_errors << [pi.errors]
        end
      end
      if !pis_errors.empty?
        error_msg(ErrorCodes::OBJECT_ERROR, "#{I18n.t "publication_identifiers.errors.create_error"}", pis_errors)
        error = true
        raise ActiveRecord::Rollback
      else
        @response[:publication][:publication_identifiers] = pis
      end
    end 

  end
  
  # !!! find_current_person moved to app/controllers/concerns/publications_controller_helper.rb

  def find_diff_since_review(publication:, person_id:)
    p2p = People2publication.where(person_id: person_id).where(publication_id: publication.id).first
    if !p2p || p2p.reviewed_publication.nil?
      return {}
    else
      # Add diffs from publication object
      diff = publication.review_diff(p2p.reviewed_publication)
      
      # Add diffs from affiliations
      oldp2p = People2publication.where(person_id: person_id).where(publication_id: p2p.reviewed_publication.id).first

      if oldp2p
        old_affiliations = oldp2p.departments2people2publications.map {|x| x.department_id}
        new_affiliations = p2p.departments2people2publications.map {|x| x.department_id}

        unless (old_affiliations & new_affiliations == old_affiliations) && (new_affiliations & old_affiliations == new_affiliations)
          diff[:affiliation] = {from: Department.where(id: old_affiliations), to: Department.where(id: new_affiliations)}
        end
      end
      
      diff[:reviewed_at] = oldp2p.reviewed_at
      return diff
    end
  end

  def handle_file_import raw_xml
    if raw_xml.blank?
      error_msg(ErrorCodes::VALIDATION_ERROR, "#{I18n.t "publications.errors.no_data_in_file"}")
      render_json
      return
    end

    xml = Nokogiri::XML(raw_xml)
    if !xml.errors.empty?
      error_msg(ErrorCodes::VALIDATION_ERROR, "#{I18n.t "publications.errors.invalid_file"}", xml.errors)
      render_json
      return
    end

    # check versions
    version_list = xml.search('//source-app').map do |element|
      element.attr("version").to_f
    end
    version_list = version_list.select! do |version|
      version < 8
    end
    if !version_list.empty?
      error_msg(ErrorCodes::VALIDATION_ERROR, "#{I18n.t "publications.errors.unsupported_endnote_version"}")
      render_json
      return
    end

    record_count = 0
    record_total = 0
    return_pub = {}

    xml.search('//xml/records/record').each do |record|
      record_total += 1
      params[:publication] = {}
      endnote = Endnote.parse(record)
      if endnote
        params[:publication].merge!(endnote.as_json)
      else
        params[:publication][:title] = "[Title not found]"
      end

      create_basic_data
      pub = Publication.new(permitted_params(params))
      if pub.save
        record_count += 1
        if record_count == 1
          return_pub = pub
        end
      else
        error_msg(ErrorCodes::VALIDATION_ERROR, "#{I18n.t "publications.errors.update_error"}", pub.errors)
        render_json
        return
      end
    end
    @response[:publication] = return_pub
    @response[:meta] = {result: {count: record_count, total: record_total}}
    render_json(201)
  end

  def import_file
    handle_file_import params[:file].read
  end


  def create_basic_data
    pubid = Publication.get_next_pubid
    params[:publication][:pubid] = pubid
    params[:publication][:is_deleted] = false
    params[:publication][:publication_type] = nil
    params[:publication][:publanguage] ||= 'en'
  end

  def permitted_params(params)
    params.require(:publication).permit(PublicationType.get_all_fields + global_params)
  end

  # Params which are not defined by publication type
  def global_params
    [:pubid, :publication_type, :is_draft, :is_deleted, :created_at, :created_by, :updated_by, :biblreviewed_at, :biblreviewed_by, :bibl_review_start_time, :bibl_review_delay_comment, :content_type, :xml, :datasource, :sourceid, :category_hsv_local => [], :series => [], :project => []]
  end

  # Creates connections between people, departments and mpublications for a publication and a people array
  def create_affiliation (publication_id:, person:, position:, reviewed_at: nil, reviewed_publication_id: nil)
    p2p = {person_id: person[:id], position: position, departments2people2publications: person[:departments]}
    p2p_obj = People2publication.create({publication_id: publication_id, person_id: p2p[:person_id], position: position, reviewed_at: reviewed_at, reviewed_publication_id: reviewed_publication_id})
    department_list = p2p[:departments2people2publications]
    if department_list.present?
      department_list.each.with_index do |d2p2p, j|
        Departments2people2publication.create({people2publication_id: p2p_obj.id, department_id: d2p2p[:id], position: j + 1})
        # Set affiliated flag to true when a person gets a connection to a department.
        Person.find_by_id(person[:id]).update_attribute(:affiliated, true)
      end
    end
  end

  def is_date_valid? date
    begin
      Time.parse(date)
    rescue 
      return false
    end
    return true
  end
end
