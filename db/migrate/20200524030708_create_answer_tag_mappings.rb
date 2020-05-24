class CreateAnswerTagMappings < ActiveRecord::Migration
  def change
    create_table :answer_tag_mappings do |t|
      t.references :answer, index: true, foreign_key: true
      t.references :tag_prompt, index: true, foreign_key: true
      t.timestamps null: false
    end
  end
end
