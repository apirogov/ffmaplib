#!/usr/bin/env ruby
# encoding: UTF-8
#Small library to work with the ffmap-d3 nodes.json
#including some combinable filters and utilities
#Copyright (C) 2012 Anton Pirogov
#Licensed under the GPLv3
require 'open-uri'
require 'json'

DEFAULT_NODESRC = 'http://burgtor.ffhl/mesh/nodes.json'

class NodeLink
  attr_accessor :to, :type, :quality

  def initialize(to, type, quality=nil)
    @to = to
    @type = type
    @quality = quality
  end

  def inspect
    "<Link to \"#{@to.class == String ? @to : (@to.name.empty? ? @to.id : @to.name)}\" :#{@type} #{@quality ? @quality : ''}>"
  end
end

class Node
  attr_accessor :id, :name, :macs, :geo
  attr_accessor :client, :online, :gateway
  attr_accessor :links

  def initialize(i,n,m,c,o,gw,geo)
    @id = i
    @name = n
    @client = c
    @online = o
    @gateway = gw
    @macs = m.class == String ? m.split(/,\s*/) : m
    @geo = geo.class == String ? geo.split(/,\s*/) : geo
    @links = []
  end

  def inspect
    "<Node[#{@name.empty? ? '' : '"'+@name+'", '}\"#{@id}\"] flags: [#{@online ? 'On ' : ''}#{@client ? 'Cl ' : ''}#{@gateway ? 'Gw ' : ''}] #{@macs} Links: #{@links}>"
  end

  #--- Link filters ---

  #return all linked nodes
  def neighbors
    NodeWrapper.new @links.map(&:to)
  end

  #return linked client node indexes
  def clients
    NodeWrapper.new @links.select{|e| e.type == :client}.map(&:to)
  end

  #return linked vpn node indexes
  def vpns
    NodeWrapper.new @links.select{|e| e.type == :vpn}.map(&:to)
  end

  #return linked mesh node indexes
  def meshs
    NodeWrapper.new @links.select{|e| e.type == :mesh}.map(&:to)
  end

  #----

  def to_json
    n = {}
    n['online'] = @online
    n['gateway'] = @gateway
    n['client'] = @client
    n['id'] = @id
    n['name'] = @name
    n['macs'] = @macs
    n['geo'] = @geo
    n['links'] = @links.map do |l|
      {'to' => l.to.id, 'type' => l.type, 'quality' => l.quality}
    end
    n
  end

  def self.from_json(h)
    n = self.new(h['id'],h['name'],h['macs'],h['client'],h['online'],h['gateway'],h['geo'])
    n.links = h['links'].map{|l| NodeLink.new l['to'], l['type'], l['quality'] }
    n
  end

end

class NodeWrapper
  #init with node array (as array wrapper) or with json file path
  def initialize(dat)
    if dat.class == Array
      @nodes = dat
      return
    end

    data = JSON.parse open(dat, 'r:UTF-8').read

    @nodes = []
    data['nodes'].each do |n|
      @nodes << Node.new(n['id'], n['name'], n['macs'], \
        n['flags']['client'], n['flags']['online'], n['flags']['gateway'], \
        n['geo'])
    end
    data['links'].each do |l|
      src, dst = l['source'], l['target']
      quality = type = nil

      if l['type']=='client'
        type = :client
      elsif l['type']=='vpn'
        type = :vpn
      else
        type = :mesh
      end

      if type != :client
        quality = l['quality'].split(/,\s*/).map(&:to_f)
      end

      if type == :client
        @nodes[src].links << NodeLink.new(@nodes[dst], type)
        @nodes[dst].links << NodeLink.new(@nodes[src], type)
      else
        @nodes[src].links << NodeLink.new(@nodes[dst], type, quality[0])
        @nodes[dst].links << NodeLink.new(@nodes[src], type, quality[1]) if quality.length > 1
      end
    end
  end

  # chainable selectors

  def unnamed
    self.class.new @nodes.select{|e| e.name.empty?}
  end

  def named
    self.class.new @nodes.select{|e| !e.name.empty?}
  end

  def clients
    self.class.new @nodes.select(&:client)
  end

  def routers
    self.class.new @nodes.select{|e| !e.client}
  end

  def gateways
    self.class.new @nodes.select(&:gateway)
  end

  def online
    self.class.new @nodes.select(&:online)
  end

  def offline
    self.class.new @nodes.select{|e| !e.online}
  end

  def located
    self.class.new @nodes.select(&:geo)
  end

  def mesh_only
    self.class.new @nodes.select{|e| e.meshs.length>0 && e.vpns.length==0}
  end

  def vpn_only
    self.class.new @nodes.select{|e| e.vpns.length>0 && e.meshs.length==0}
  end

  #---- useful forwardings and overrides ----

  #find by name or mac or access by index or range
  def [](n)
    if n.class == String
      ret = @nodes.find{|e| e.name == n}
      ret = @nodes.find{|e| e.macs.index(n)} if !ret
      return ret
    end
    @nodes[n]
  end

  def index(n)
    @nodes.index n
  end

  def length
    @nodes.length
  end

  #---- data reduction ----

  #unbox (necessary for select, each, map etc custom filters)
  def to_a
    @nodes
  end

  #return array of just the node names of the set
  def names
    @nodes.map(&:name)
  end

  #return just ID MACs of the node set (e.g. useful for clients)
  def ids
    @nodes.map(&:id)
  end

  #---- serialization ----

  #return JSONable hash
  def to_json
    @nodes.map(&:to_json)
  end

  #return JSON parsed hash
  def self.from_json(data)
    nodes = data.map{|e| Node.from_json e}
    wrap = self.new nodes
    nodes.each{|e| e.links.each{|l| l.to = wrap[l.to]}}
    wrap
  end
end
