class PeopleSearchEngine < SearchEngine
  def self.solr
    @@solr ||= RSolr.connect(url: APP_CONFIG['person_index_url'])
  end

  def solr
    PeopleSearchEngine.solr
  end

  def self.query(query, start, rows)

    query_fields = [
      'id^100',
      'xaccount^100',
      'orcid^100',
      'full_name^50',
      'first_name^10',
      'last_name^10',
      'year_of_birth^5',
      'alternative_names'
    ]

    solr.paginate(start, rows, "select", params: {
      "defType" => "edismax",
      q: query,
      qf: query_fields.join(" "),
      fl: "score,*"})
  end

  def self.update_search_engine person
    if Rails.env == "test"
      self.update_search_engine_do person
    else
      Thread.new {
        ActiveRecord::Base.connection_pool.with_connection do
          self.update_search_engine_do person
        end
      }
    end
  end

  def self.delete_from_search_engine person_id
    if Rails.env == "test"
      self.delete_from_search_engine_do person_id
    else
      Thread.new {
        ActiveRecord::Base.connection_pool.with_connection do
          self.delete_from_search_engine_do person_id
        end
      }
    end
  end

  def self.update_search_engine_do person
    search_engine = PeopleSearchEngine.new
    search_engine.delete_from_index(id: person.id)
    document = create_document person
    search_engine.add(data: document)
  ensure
    search_engine.commit
  end

  def self.delete_from_search_engine_do person_id
    search_engine = PeopleSearchEngine.new
    search_engine.delete_from_index(id: person_id)
  ensure
    search_engine.commit
  end

  def self.create_document person
    # Departments
    document = {
      departments_id: [],
      departments_name_en: [],
      departments_name_sv: [],
      departments_start_year: [],
      departments_end_year: []
    }
    person.get_all_departments.each do |department|
      document[:departments_id] << department.id
      document[:departments_name_en] << department.name_en
      document[:departments_name_sv] << department.name_sv
      document[:departments_start_year] << (department.start_year.present? ? department.start_year : -1)
      document[:departments_end_year] << (department.end_year.present? ? department.end_year : -1)
    end
    document.merge({
      id: person.id,
      year_of_birth: person.year_of_birth,
      first_name: person.first_name,
      last_name: person.last_name,
      created_at: person.created_at,
      updated_at: person.updated_at,
      created_by: person.created_by,
      updated_by: person.updated_by,
      xaccount: person.get_identifier(source: 'xkonto'),
      orcid: person.get_identifier(source: 'orcid'),
      identifiers: person.identifiers.map{ |i| i.value },
      alternative_names: person.alternative_names.map{ |an| an.first_name.nil? ? + an.last_name : an.first_name + " " + an.last_name},
      has_active_publications: person.has_active_publications?
    })
  end
end
