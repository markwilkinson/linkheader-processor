
module LinkHeaders
  class LinkFactory

    # @return [<String>] the HTTP anchor used by default for implicit Links
    attr_accessor :default_anchor
    # @return [Array] An array of strings containing any warnings that were encountered when creating the link (e.g. duplicate cite-as but non-identical URLs)
    attr_accessor :warnings
    attr_accessor :all_links

    #
    # Create the LinkFacgtory Object
    #
    # @param [String] default_anchor The URL to be used as the default anchor for a link when it isn't specified
    #
    def initialize(default_anchor: 'https://example.org/')
      @default_anchor = default_anchor
      @warnings = Array.new
      @all_links = Array.new
    end


    #
    # Create a new LinkHeader::Link object
    #
    # @param [Symbol] responsepart either :header, :body, or :linkset as the original location of this Link
    # @param [String] href the URL of the link
    # @param [String] relation the string of the relation type (e.g. "cite-as" or "described-by")
    # @param [String] anchor The URL of the anchor.  Defaults to the default anchor of the LinkHeader factory
    # @param [Hash] **kwargs All other facets of the link. e.g. 'type' => 'text/html',...
    #
    # @return [LinkHeader::Link] The Link object just created
    #
    def new_link(responsepart:, href:, relation:, anchor: @default_anchor, **kwargs)
      # warn "creating new link with kw #{kwargs}"
      if relation.split(/\s/).length > 1
        @warnings |= ['WARN: the link relation contains spaces.  This is allowed by the standard to indicate multiple relations for the same link, but this MUST be processed before creating a LinkHeaders::Link object!']
      end

      link = LinkHeaders::Link.new(responsepart: responsepart, factory: self, href: href, anchor: anchor, relation: relation, **kwargs)
      link = sanitycheck(link)  # this will add warnings if the link already exists and has a conflict.  returns the original of a duplicate
      self.all_links |= [link]
      return link
    end

    #
    # retrieve all known LinkHeader::Link objects
    #
    # @return [Array] Array of all LinkHeader::Link objects created by the factory so far
    #
    def all_links
      @all_links
    end

    #
    # Extracts Linkset type links from a list of LinkHeader::Link objects
    #
    # @return [Array] Array of LinkHeader::Link objects that represent URLs of LinkSets.
    #
    def linksets
      links = Array.new
      self.all_links.each do |link|
        # warn "found #{link.relation}"
        next unless link.relation == 'linkset'
        links << link
      end
     links
    end

    #
    # Extracts the LinkHeader::Link ojects that originated in the HTTP Headers
    #
    # @return [Array]  Array of LinkHeader::Link objects 
    #
    def headlinks
      links = Array.new
      self.all_links.each do |link|
        # warn "found #{link.relation}"
        next unless link.responsepart == :header
        links << link
      end
      links
    end

    #
    # Extracts the LinkHeader::Link ojects that originated in the HTML Link Headers
    #
    # @return [Array]  Array of LinkHeader::Link objects
    #
    def bodylinks
      links = Array.new
      self.all_links.each do |link|
        # warn "found #{link.relation}"
        next unless link.responsepart == :body
        links << link
      end
      links
    end

    #
    # Extracts the LinkHeader::Link ojects that originated from a LinkSet
    #
    # @return [Array]  Array of LinkHeader::Link objects
    #
    def linksetlinks
      links = Array.new
      self.all_links.each do |link|
        # warn "found #{link.relation}"
        next unless link.responsepart == :linkset
        links << link
      end
      links
    end

    def sanitycheck(link)
      if link.relation == "describedby" and !(link.respond_to? 'type')
        @warnings |= ['WARN: A describedby link should include a "type" attribute, to know the MIME type of the addressed description']
      end

      self.all_links.each do |l|
        if l.relation == "cite-as" and link.relation == "cite-as"
          if l.href != link.href
            @warnings |= ['WARN: Found conflicting cite-as relations.  This should never happen']
          end
        end
        if l.href == link.href
          if l.relation != link.relation
            @warnings |= ['WARN: Found identical hrefs with different relation types.  This may be suspicious. Both have been retained']
          else
            @warnings |= ["WARN: found apparent duplicate #{l.relation} #{l.href} EQUALS#{link.href}. Ignoring and returning known link #{l.relation} #{l.href}"]
            link = l
          end
        end
      end
      link
    end
  end

  #
  # LinkHeader::Link represnts an HTTP Link Header, an HTML LinkHeader, or a LinkSet Link.
  #
  # #anchor, #href, and #relation are all guaranteed to return a value.  Other methods are dynamically created based on what key/value pairs exist in the link
  # for example, if "'type': 'text/html'" exists in the link description, then the method #type will be available on the Link object.
  #
  class Link
    # @return [String] URL of the Link anchor
    attr_accessor :anchor 
    # @return [String] URL of the Link
    attr_accessor :href
    # @return [String] What is the relation? (e.g. "cite-as")
    attr_accessor :relation
    # @return [LinkHeader::LinkFactory] The factory that made the Link
    attr_accessor :factory
    # @return [Symbol] :header, :body, or :linkset indicating the place the Link object originated
    attr_accessor :responsepart
    # @return [String] the list of instance method names auto-generated by the various key/value pairs in the link header.  e.g. "type"
    attr_accessor :linkmethods
    

    #
    # Create the Link object
    #
    # @param [Symbol] responsepart :header, :body, :linkset
    # @param [LinkHeader::LinkFactory] factory the factory that made the link
    # @param [String] href The URL of the Link
    # @param [String] anchor The URL of the anchor
    # @param [String] relation the Link relation (e.g. "cite-as")
    # @param [hash] **kwargs The remaining facets of the link (e.g. type => 'text/html')
    #
    def initialize(responsepart:, factory:, href:, anchor:, relation:, **kwargs)
      # warn "incoming kw args #{kwargs}"
      @href = href
      @anchor = anchor
      @relation = relation
      @factory = factory
      @responsepart = responsepart
      @linkmethods = Array.new

      kwargs.each do |k, v|
        # warn "key #{k} val #{v}"

        @linkmethods << k
        define_singleton_method(k.to_sym) {
          value = instance_variable_get("@#{k}")
          return value
        } 
        define_singleton_method "#{k}=".to_sym do |val|
          instance_variable_set("@#{k}", val)
          return "@#{k}".to_sym
        end
        # warn "methods:  #{self.methods - Object.new.methods}"
        self.send("#{k}=", v)
      end
    end

    #
    # Create an HTML version of the link
    # @return [String]  HTML version of the Link object
    #
    def to_html
      methods = self.linkmethods
      href = self.href
      rel = self.relation
      anchor = self.anchor
      properties = []
      methods.each do |method|
        value = self.send(method)
        properties << [method, value]
      end
      properties << ["rel", rel]
      properties << ["anchor", anchor]
      LinkHeader::Link.new(href, properties).to_html
    end
  end
end
