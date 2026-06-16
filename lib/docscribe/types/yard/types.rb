# frozen_string_literal: true

module Docscribe
  module Types
    module Yard
      Named = Struct.new(:name, keyword_init: true)
      Generic = Struct.new(:base, :args, keyword_init: true)
      Union = Struct.new(:types, keyword_init: true)
      Intersection = Struct.new(:types, keyword_init: true)
      Optional = Struct.new(:type, keyword_init: true)
      Tuple = Struct.new(:types, keyword_init: true)
      HashMap = Struct.new(:key_type, :value_type, keyword_init: true)
      Duck = Struct.new(:method_names, keyword_init: true)
      Literal = Struct.new(:value, keyword_init: true)
    end
  end
end
