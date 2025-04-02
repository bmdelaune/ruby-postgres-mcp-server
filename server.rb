#!/usr/bin/env ruby
$LOAD_PATH.unshift(File.expand_path(File.join(File.dirname(__FILE__), 'lib')))

require 'json'
require 'json-schema'
require 'dry-schema'
require 'dry-validation'
require 'concurrent'
require 'pg'
require "model_context_protocol"

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
    # Make sure conn is your PG connection object
    result = conn.exec("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")

    resources = result.map do |row|
      table_name = row["table_name"]
      uri = "#{resource_base_url}/#{table_name}/#{SCHEMA_PATH}"
      {
        uri: uri,
        mimeType: "application/json",
        name: "\"#{table_name}\" database schema"
      }
    end

    { resources: resources }
  rescue => e
    { resources: [] }
  end
end

# Add resource reading capability using PG directly
server.override_request_handler("resources/read") do |params|
  begin
    uri = params[:uri]

    resource_url = URI.parse(uri)
    path_components = resource_url.path.split("/")
    schema = path_components.pop
    table_name = path_components.pop

    if schema != SCHEMA_PATH
      raise "Invalid resource URI"
    end

    # Query for table columns using PG
    result = conn.exec_params(
      "SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_name = $1",
      [table_name]
    )

    if result.ntuples > 0
      contents = [{
        uri: uri,
        mimeType: "application/json",
        text: JSON.generate(result.map { |row| row })
      }]

      { contents: contents }
    else
      raise "Table '#{table_name}' not found"
    end
  rescue => e
    { error: e.message }
  end
end

# List resources handler
server.tool("list_resources", {
  "type": "object",
  "properties": {}
}) do |params|
  begin
    result = conn.exec("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")
    resources = result.map do |row|
      table_name = row["table_name"]
      uri = "#{resource_base_url}/#{table_name}/#{SCHEMA_PATH}"
      {
        uri: uri,
        mimeType: "application/json",
        name: "\"#{table_name}\" database schema"
      }
    end

    {
      content: [
        { type: "text", text: JSON.generate({ resources: resources }) }
      ]
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

# Read resource handler
server.tool("read_resource", {
  "type": "object",
  "properties": {
    "uri": {
      "type": "string"
    }
  },
  "required": ["uri"]
}) do |params|
  begin
    resource_url = URI.parse(params[:uri])
    path_components = resource_url.path.split("/")
    schema = path_components.pop
    table_name = path_components.pop

    if schema != SCHEMA_PATH
      raise "Invalid resource URI"
    end

    result = conn.exec_params(
      "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = $1",
      [table_name]
    )

    {
      content: [
        {
          type: "text",
          text: JSON.generate({
            contents: [
              {
                uri: params[:uri],
                mimeType: "application/json",
                text: JSON.generate(result.to_a)
              }
            ]
          })
        }
      ]
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

# Query tool
server.tool("query", {
  "type": "object",
  "properties": {
    "sql": {
      "type": "string",
      "description": "A Postgres SQL query string"
    }
  },
  "required": ["sql"]
}) do |params|
  begin
    sql = params[:sql]
    conn.exec("BEGIN TRANSACTION READ ONLY")
    result = conn.exec(sql)

    {
      content: [
        { type: "text", text: JSON.generate(result.to_a) }
      ]
    }
  rescue => e
    {
      content: [
        { type: "text", text: "Error: #{e.message}" }
      ],
      is_error: true
    }
  ensure
    begin
      conn.exec("ROLLBACK")
    rescue => e
      puts "Could not roll back transaction: #{e.message}"
    end
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

