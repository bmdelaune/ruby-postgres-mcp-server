#!/usr/bin/env ruby

require 'json'
require 'json-schema'
require 'dry-schema'
require 'dry-validation'
require 'concurrent'
require 'pg'
require 'faraday'
require './model_context_protocol/lib/model_context_protocol.rb'

database_url = ENV["DATABASE_URL"]
resource_base_url = URI.parse(database_url)
resource_base_url.scheme = "postgres"
resource_base_url.password = ""

# Create connection pool
conn = PG.connect(database_url)
SCHEMA_PATH = "schema"

# Create an MCP server
server = ModelContextProtocol::Server::McpServer.new({
  name: "Ruby PostgreSQL MCP Example",
  version: "0.1.0"
})

# Add resource listing capability using PG directly
server.override_request_handler("resources/list") do |params|
  begin
     resources = []

    { resources: resources }
  rescue => e
    { resources: [] }
  end
end

# Add resource reading capability using PG directly
server.override_request_handler("resources/read") do |params|
  begin
      contents = []

      { contents: contents }
  rescue => e
    { error: e.message }
  end
end

# Read resource handler
server.tool("get_recent_flow_instance_errors", { type: "object", properties: {}}) do |params|
  begin
    result = Faraday.get('http://@host.docker.local:5000/api/v1/flow_instances/recent')

    flow_instances = JSON.parse(result.body).dig("results")

    {
      content: flow_instances.map do |flow_instance|
        {
          type: "text",
          text: JSON.generate({
            contents: [
              {
                uri: "http://@host.docker.local:5000/api/v1/flow_instances/#{flow_instance.dig("id")}",
                mimeType: "application/json",
                text: JSON.generate(flow_instance)
              }
            ]
          })
        }
      end
    }
  rescue => e
    {
      content: [
        { type: "text", text: "Error: #{e.message}" }
      ],
      is_error: true
    }
  end
end

# Start receiving messages on stdin and sending messages on stdout
transport = ModelContextProtocol::Server::StdioServerTransport.new
server.connect(transport)
# transport.send_message({ "type": "connected", "text":  "Connected to server" })

# Keep the process running
begin
  sleep
rescue Interrupt
  # Handle Ctrl+C
end

