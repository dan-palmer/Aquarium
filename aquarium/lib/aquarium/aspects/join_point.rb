require 'aquarium/utils'
  
def bad_attributes message, options
  raise Aquarium::Utils::InvalidOptions.new("Invalid attributes. " + message + ". Options were: #{options.inspect}")
end

module Aquarium
  module Aspects
    class JoinPoint

      class Context
        attr_accessor :advice_kind, :advised_object, :parameters, :block_for_method, :returned_value, :raised_exception, :proceed_proc

        alias :target_object  :advised_object
        alias :target_object= :advised_object=
        
        def initialize options
          update options
          assert_valid options
        end

        def update options
          options.each do |key, value|
            instance_variable_set "@#{key}".intern, value
          end
        end
    
        def proceed enclosing_join_point, *args, &block
          raise "It looks like you tried to call \"JoinPoint#proceed\" (or \"JoinPoint::Context#proceed\") from within advice that isn't \"around\" advice. Only around advice can call proceed. (Specific error: JoinPoint#proceed cannot be called because no \"@proceed_proc\" attribute was set on the corresponding JoinPoint::Context object.)" unless @proceed_proc
          args = parameters if (args.nil? or args.size == 0)
          enclosing_join_point.context.block_for_method = block if block 
          proceed_proc.call enclosing_join_point, *args
        end
        protected :proceed
        
        alias :to_s :inspect
    
        # We require the same object id, not just equal objects.
        def <=> other
          return 0 if object_id == other.object_id 
          return 1 if other.nil?
          result = self.class <=> other.class 
          return result unless result == 0
          result = (self.advice_kind.nil? and other.advice_kind.nil?) ? 0 : self.advice_kind <=> other.advice_kind 
          return result unless result == 0
          result = (self.advised_object.object_id.nil? and other.advised_object.object_id.nil?) ? 0 : self.advised_object.object_id <=> other.advised_object.object_id 
          return result unless result == 0
          result = (self.parameters.nil? and other.parameters.nil?) ? 0 : self.parameters <=> other.parameters 
          return result unless result == 0
          result = (self.returned_value.nil? and other.returned_value.nil?) ? 0 : self.returned_value <=> other.returned_value 
          return result unless result == 0
          (self.raised_exception.nil? and other.raised_exception.nil?) ? 0 : self.raised_exception <=> other.raised_exception
        end
    
        def eql? other
          (self <=> other) == 0
        end

        alias :==  :eql?
        alias :=== :eql?
    
        protected
    
        def assert_valid options
          bad_attributes("Must specify an :advice_kind", options)    unless advice_kind
          bad_attributes("Must specify an :advised_object", options) unless advised_object
          bad_attributes("Must specify a :parameters", options)      unless parameters
        end    
      end

      attr_accessor :target_type, :target_object, :method_name, :visibility, :context
      attr_reader   :instance_or_class_method
      
      def instance_method?
        @instance_method
      end
      
      def class_method?
        !@instance_method
      end
      
      def initialize options = {}
        @target_type     = options[:type]
        @target_object   = options[:object]
        @method_name     = options[:method_name] || options[:method]
        class_method     = options[:class_method].nil? ? false : options[:class_method]
        @instance_method = options[:instance_method].nil? ? (!class_method) : options[:instance_method]
        @instance_or_class_method  = @instance_method ? :instance : :class
        @visibility = Aquarium::Utils::MethodUtils.visibility(type_or_object, @method_name, class_or_instance_method_flag)
        assert_valid options
      end
  
      def type_or_object
        target_type || target_object
      end
      
      alias_method :target_type_or_object, :type_or_object

      def exists?
        type_or_object_sym = @target_type ? :type : :object
        results = Aquarium::Finders::MethodFinder.new.find type_or_object_sym => type_or_object, 
                            :method => method_name, 
                            :options => [visibility, instance_or_class_method]
        raise Exception("MethodFinder returned more than one item! #{results.inspect}") if (results.matched.size + results.not_matched.size) != 1
        return results.matched.size == 1 ? true : false
      end
      
      def proceed *args, &block
        context.method(:proceed).call self, *args, &block
      end

      def make_current_context_join_point context_options
        new_jp = dup
        if new_jp.context.nil?
          new_jp.context = JoinPoint::Context.new context_options
        else
          new_jp.context = context.dup
          new_jp.context.update context_options
        end
        new_jp
      end

      # We require the same object id, not just equal objects.
      def <=> other
        return 0  if object_id == other.object_id 
        return 1  if other.nil?
        result = self.class <=> other.class 
        return result unless result == 0
        result = (self.target_type.nil? and other.target_type.nil?) ? 0 : self.target_type.to_s <=> other.target_type.to_s 
        return result unless result == 0
        result = (self.target_object.nil? and other.target_object.nil?) ? 0 : self.target_object.object_id <=> other.target_object.object_id 
        return result unless result == 0
        result = (self.method_name.nil? and other.method_name.nil?) ? 0 : self.method_name.to_s <=> other.method_name.to_s 
        return result unless result == 0
        result = self.instance_method? == other.instance_method?
        return 1 unless result == true
        return  0 if  self.context.nil? and  other.context.nil?
        return -1 if  self.context.nil? and !other.context.nil?
        return  1 if !self.context.nil? and other.context.nil?
        return self.context <=> other.context 
      end

      def eql? other
        return (self <=> other) == 0
      end
  
      alias :==  :eql?
      alias :=== :eql?
  
      def inspect
        "JoinPoint: {target_type = #{target_type.inspect}, target_object = #{target_object.inspect}, method_name = #{method_name}, instance_method? #{instance_method?}, context = #{context.inspect}}"
      end
  
      alias :to_s :inspect

  
      protected
  
      # Since JoinPoints can be declared for non-existent methods, tolerate "nil" for the visibility.
      def assert_valid options
        error_message = ""
        error_message << "Must specify a :method_name. "            unless method_name
        error_message << "Must specify either a :type or :object. " unless (target_type or  target_object)
        error_message << "Can't specify both a :type or :object. "  if     (target_type and target_object)
        bad_attributes(error_message, options) if error_message.length > 0
      end

      def class_or_instance_method_flag
        "#{instance_or_class_method.to_s}_method_only".intern
      end
    
      public
  
      NIL_OBJECT = Aquarium::Utils::NilObject.new  
    end
  end
end
