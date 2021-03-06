class ProductTest
  include Mongoid::Document

  belongs_to :product
  has_one :patient_population
  has_many :test_executions, dependent: :delete
  belongs_to :user

  embeds_many :notes, inverse_of: :product_test

  # Test Details
  field :name, type: String
  field :description, type: String
  field :effective_date, type: Integer
  field :measure_ids, type: Array
  field :population_creation_job, type: String
  field :result_calculation_jobs, type: Hash

  validates_presence_of :name
  validates_presence_of :effective_date
  
  around_destroy :destroy_records
  
  # Returns true if this ProductTests most recent TestExecution is passing
  def passing?
    return false if self.test_executions.empty?
    
    most_recent_execution = self.ordered_executions.first
    return !most_recent_execution.nil? && most_recent_execution.passing?
  end
  
  # Returns a list of associated executions that are ordered from most recent to oldest
  def ordered_executions
    return self.test_executions.sort! {|e1, e2| e2.execution_date <=> e1.execution_date}
  end
  
  # Return all measures that are selected for this particular ProductTest
  def measure_defs
    return [] if !measure_ids
    
    self.measure_ids.collect do |measure_id|
      Measure.where(id: measure_id).order_by([[:sub_id, :asc]]).all()
    end.flatten
  end
  
  # Returns the number of measures that this ProductTest is actually looking at.
  def count_measures
    measures = 0
    
    self.measure_ids.each do |measure|
      measures += 1 if !measure.empty?
    end
    
    return measures
  end
  
  # Check to see if this population was imported by the vendor
  def imported_population?
    return self.patient_population.nil?
  end

  def destroy
    # Gather all records and their IDs so we can delete them along with every associated entry in the patient cache
    records = Record.where(:test_id => self.id)
    record_ids = records.map { _id }
    MONGO_DB.collection('patient_cache').remove({'value.patient_id' => {"$in" => record_ids}})
    records.destroy
    self.delete
  end
  
  # Used for downloading and e-mailing the records associated with this test.
  #
  # Returns a file that represents the test's patients given the requested format.
  def generate_records_file(format)
    file = Tempfile.new("patients-#{Time.now.to_i}")
    patients = Record.where("test_id" => self.id)
    
    if format == 'csv'
      Cypress::PatientZipper.flat_file(file, patients)
    else
      Cypress::PatientZipper.zip(file, patients, format.to_sym)
    end
    
    file
  end
end