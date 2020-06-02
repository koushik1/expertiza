class MetricsQuery
#The certainty threshold is the fraction (between 0 and 1) that says how certain the ML algorithm
# must be of a tag value before it will ask the author to tag it manually.
TAG_CERTAINTY_THRESHOLD = 0.8

  # answer_tagging: this method calls the WS to determine which tags need to be rendered
  # for manual inputs in order to increase the bot's confidence on its next judgment.
  # The result that the web-service sends back is formatted as
  #             { answer_id_1 => [tag_prompt_id_1, tag_prompt_id_2],
  #               answer_id_2 => [tag_prompt_id_3], ...}
  # to associate each answer with tags that the bot is confident of
  # (or in other words, tagged by the bot).
  def get_tagged_answer_prompts(answers, tag_prompt_deployments)
    # step 1. transform answers to a format that can be understood by the WS
    tagged_answer_prompts = Hash.new(|hash, key| hash[key] = [])
    ws_input = {'reviews': []}
    answers.each do |answer|
      ws_input["reviews"].push({'id': answer.id, 'text': answer.comments})
    end

    # this is rather hard-coded, need to find a way to link each tag_prompt with its
    # corresponding web service call
    # we create a dict which maps tag prompts to their relevant API endpoints
    metrics = { 'prompt_1' => 'problems', 'prompt_2' => 'suggestions', 'prompt_3' => 'emotions', 'prompt_5' => 'sentiments'}
    tag_prompt_deployments.each do |tag_dep|
      promt_text = TagPrompt.find(tag_dep.tag_prompt_id).prompt
      metric = metrics[promt_text]

      # step 2. pass ws_input to web service and use the response to construct a hash
      # which maps answer_id to tag_prompt_id
      url = WEBSERVICE_CONFIG['metareview_webservice_url'] + metric
      begin
        response = RestClient.post url, ws_input.to_json, content_type: :json, accept: :json
        ws_output = JSON.parse(response)["reviews"]
        ws_output.each do |review|
          tagged_answer_prompts[review.id].push(tag_dep.tag_prompt_id) if review['confidence'] >= TAG_CERTAINTY_THRESHOLD
        end
      rescue StandardError => e
        # at any time the StandardError occur, return nil so we don't render partial result
        return nil
      end
    end
    tagged_answer_prompts
  end
end