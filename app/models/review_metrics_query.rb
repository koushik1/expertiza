class ReviewMetricsQuery
  include Singleton

  # The certainty threshold is the fraction (between 0 and 1) that says how certain
  # the ML algorithm must be of a tag value before it will ask the author to tag it
  # manually.
  TAG_CERTAINTY_THRESHOLD = 0.8

  # link each tag prompt to the corresponding key in the review hash
  PROMPT_TO_METRIC = {'Mention Problems?' => 'problem',
                      'Suggest Solutions?' => 'suggestions',
                      'Mention Praise?' => 'sentiment',
                      'Positive Tone?' => 'emotions'}.freeze

  def initialize
    # @queried_results: an array of AnswerTag objects
    @queried_results = []
  end

  def confidence(tag_prompt_deployment_id, review_id)
    review = retrieve_from_cache(tag_prompt_deployment_id, review_id)
    review ? review.confidence_level : 0
  end

  def has?(tag_prompt_deployment_id, review_id)
    review = retrieve_from_cache(tag_prompt_deployment_id, review_id)
    review ? review.value == '1' : false
  end

  def retrieve_from_cache(tag_prompt_deployment_id, review_id)
    tag = @queried_results.find {|tag| tag.answer.id == review_id && tag.tag_prompt_deployment.id == tag_prompt_deployment_id }
    tag ||= AnswerTag.where(answer_id: review_id, tag_prompt_deployment_id: tag_prompt_deployment_id).where.not(confidence_level: nil).first

    # if pre-cached tag is not present
    # unless tag
    #   # cache it, along with other reviews that may also need to be cached
    #   reviews = Answer.find(review_id).response.scores
    #   cache_ws_results(reviews, [TagPromptDeployment.find(tag_prompt_deployment_id)], false)
    #   tag = @queried_results.find {|tag| tag.answer.id == review_id && tag.tag_prompt_deployment.id == tag_prompt_deployment_id }
    # end
    tag
  end

  def cache_ws_results(reviews, tag_prompt_deployments, cache_to_db)
    ws_input = {'reviews' => []}
    reviews.each do |review|
      ws_input['reviews'] << {'id' => review.id, 'text' => review.plain_comments} if review.comments.present?
    end

    tags = []
    # ask MetricsController to make a call to the review metrics web service
    tag_prompt_deployments.each do |tag_prompt_deployment|
      tag_prompt = tag_prompt_deployment.tag_prompt
      metric = PROMPT_TO_METRIC[tag_prompt.prompt]
      begin
        ws_output = MetricsController.new.bulk_retrieve_metric(metric, ws_input, false)
        ws_output_confidence = MetricsController.new.bulk_retrieve_metric(metric, ws_input, true)
      rescue StandardError
        # skipped
      else
        next unless ws_output && ws_output['reviews'] && ws_output_confidence && ws_output_confidence['reviews']
        ws_output['reviews'].zip(ws_output_confidence['reviews']).each do |review_with_value, review_with_confidence|
          tag = AnswerTag.where(answer_id: review_with_value['id'],
                                tag_prompt_deployment_id: tag_prompt_deployment.id)
                         .where.not(confidence_level: [nil]).first_or_initialize
          tag.assign_attributes(value: translate_value(metric, review_with_value),
                                confidence_level: translate_confidence(metric, review_with_confidence))
          tags << tag
        end
      end
    end

    tags.each(&:save) if cache_to_db
    tags.each {|tag| @queried_results << tag }
    @queried_results.uniq! {|a| a.answer_id && a.tag_prompt_deployment_id }
  end

  def translate_value(metric, review)
    value = case metric
            when 'problem'
              review['problems'] == 'Present'
            when 'suggestions'
              review['suggestions'] == 'Present'
            when 'emotions'
              review['Praise'] != 'None'
            when 'sentiment'
              review['sentiment_tone'] == 'Positive'
            else
              false
            end
    value ? 1 : -1
  end

  def translate_confidence(metric, review)
    confidence = review['confidence'].to_f

    # translate the meaning of 'confidence'
    # from 'confidence of the positive'
    # to 'confidence of the predicted value (present or absent)'
    if (metric == 'problem' || metric == 'suggestions') && (confidence < 0.5) && (confidence != 0)
      1 - confidence
    else
      confidence
    end
  end

  # =============== Caller's interfaces ===============

  # usage: ReviewMetricQuery.confidence(tag_dep.id, answer.id)
  def self.confidence(tag_prompt_deployment_id, review_id)
    ReviewMetricsQuery.instance.confidence(tag_prompt_deployment_id, review_id)
  end

  # usage: ReviewMetricQuery.confident?(tag_dep.id, answer.id)
  # answer_tagging would most likely to use this method since it returns either
  # true or false
  def self.confident?(tag_prompt_deployment_id, review_id)
    confidence = ReviewMetricsQuery.instance.confidence(tag_prompt_deployment_id, review_id)
    confidence >= TAG_CERTAINTY_THRESHOLD
  end

  # usage: ReviewMetricQuery.has?(tag_dep.id, answer.id)
  def self.has?(tag_prompt_deployment_id, review_id)
    ReviewMetricsQuery.instance.has?(tag_prompt_deployment_id, review_id)
  end

  def self.average(tag_prompt_deployment_id, reviewer = nil)
    tags = AnswerTag.where(tag_prompt_deployment_id: tag_prompt_deployment_id, user_id: nil)
    if reviewer
      responses = reviewer.becomes(Participant).reviews.map(&:response).flatten
      answers = responses.map(&:scores).flatten
      tags = tags.where(answer_id: answers.map(&:id))
    end
    analyzed_responses = tags.map {|tag| tag.answer.response }.uniq
    positive_tags = tags.where(value: '1')
    analyzed_responses.count.zero? ? 0 : positive_tags.count / analyzed_responses.count
  end

  # =============== End of caller's interfaces ===============
end
