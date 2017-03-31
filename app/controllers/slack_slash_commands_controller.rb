class CommandWorker
  def connection(params)
    Faraday.new(url: params[:response_url]) do |faraday|
      faraday.adapter Faraday.default_adapter
    end
  end

  def tenk_client
    token = ENV['TENK_TOKEN'] || fail('No api token set. Set TENK_TOKEN environment variable.')
    @_client ||= Tenk.new token: token, api_base: ENV['TENK_API_BASE']
  end

  def list_projects
    projects = []
    page = 1
    retval = ''

    loop do
      response = client.projects.list(page: page)
      new_projects = response.data
      projects << new_projects
      break unless response.paging.next
      page += 1
    end

    projects.flatten!
    project_groups = projects.sort_by(&:name).group_by(&:project_state)
    project_groups.each do |state, projects|
      projects.each do |project|
        retval += "- #{project.name}\n"
      end
    end

    retval
  end

  def perform_async(params)
    command_parts = params[:text].split(' ')
    report = if command_parts[0] == 'list'
      list_projects
    else
      'Not implemented'
    end

    connection(params).post do |req|
      req.url params[:response_url]
      req.headers['Content-Type'] = 'application/json'
      req.body = JSON.generate({
        text: report
      })
    end
  end
end

class SlackSlashCommandsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    return render json: {}, status: 403 unless valid_slack_token?
    CommandWorker.new.perform_async(command_params)
    head :ok
  end

  private

  def valid_slack_token?
    params[:token] == ENV['SLACK_SLASH_TOKEN']
  end

  # Only allow a trusted parameter "white list" through.
  def command_params
    params.permit(:text, :token, :user_id, :response_url)
  end
end
