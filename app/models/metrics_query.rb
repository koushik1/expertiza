class MetricsQuery
  # answer_tagging: this method calls the WS to determine which tags need to be rendered
  # for manual inputs in order to increase the bot's confidence on its next judgment.
  # The result that the web-service sends back is formatted as
  #             { answer_id_1 => [tag_prompt_id_1, tag_prompt_id_2],
  #               answer_id_2 => [tag_prompt_id_3], ...}
  # to associate each answer with its taggable prompts

  #Setting the Tagging Threshold Constant
  TAG_CERTAINTY_CONSTANT = 0.8

  def get_taggable_answer_prompts(answers, tag_prompt_deployments)
    # step 1. transform answers to a format that can be understood by the WS
    taggable_answer_prompts = Hash.new(|hash, key| hash[key] = [])
    ws_input = {'reviews': []}
    answers.each do |answer|
      ws_input["reviews"].push({'id': answer.id, 'text': answer.comments})
    end

    # this is rather hard-coded, need to find a way to link each tag_prompt with its
    # corresponding web service call
    # we create a dict which maps tag prompt ids to their relevant API endpoints
    metrics = { 1 => 'problems', 2 => 'suggestions', 3 => 'emotions', 5 => 'sentiments'}
    tag_prompt_deployments.each do |tag_dep|
      metric = metrics[tag_dep.tag_prompt_id]

      # step 2. pass ws_input to web service and use the response to construct a hash
      # which maps answer_id to tag_prompt_id
      url = WEBSERVICE_CONFIG['metareview_webservice_url'] + metric
      begin
        response = RestClient.post url, ws_input.to_json, content_type: :json, accept: :json
        ws_output = JSON.parse(response)["reviews"]
        # let's assume that we want tags below 80% confidence to be shown to the authors
        ws_output.each do |review|
          taggable_answer_prompts[review.id].push(tag_dep.tag_prompt_id) if review['confidence'] < TAG_CERTAINTY_CONSTANT
        end
      rescue StandardError => e
        # at any time the StandardError occur, return nil so we don't render half result
        return nil
      end
    end
    taggable_answer_prompts
  end
end