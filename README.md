## privacy-genie-web

`privacy-genie-web`은 사용자의 개인정보보호 관련 질문을 받아 **문서 검색부터 LLM 답변 생성까지 전체 서비스 흐름을 제어하는 Rails 기반 웹 애플리케이션**입니다.
DB(스키마·마이그레이션·저장)와 pgvector 검색, LLM 답변은 web이 맡고, 문서 Parsing·Chunking·Embedding과 질문 임베딩은
별도의 Python 서비스인 [privacy-genie-doc](https://github.com/mady-21/privacy_genie_doc)이 맡습니다. doc은 DB에 직접 쓰지 않고
API로 데이터를 내주기만 합니다. 문서와 질문은 같은 모델(`nlpai-lab/KURE-v1`, 1024차원)로 임베딩해야 하므로 모델은 doc에만 있습니다.

### 처리 흐름

문서 적재(doc에서 원문을 다시 빌드했을 때):

```text
[web] documents:sync ──GET /documents/{act,decree}──▶ [doc] 미리 계산한 청크+벡터
[web] chunk_id 기준으로 document_chunks에 upsert, 응답에 없는 청크 삭제
```

사용자 질문:

```text
[web] 사용자 질문 ──POST /embeddings──▶ [doc] 질문 벡터
[web] pgvector로 가까운 청크 검색 → 질문 + 관련 청크 → LLM → 근거 기반 답변
```

### 문서 동기화

```bash
docker exec privacy-genie-web bin/rails documents:sync
docker exec privacy-genie-web bin/rails documents:sync TYPE=act
```

- `Documents::Sync`가 문서 하나를 트랜잭션 하나로 맞춥니다. 법률이 성공하고 시행령이 실패하면 법률은 반영된 채로 남습니다.
- 같은 응답으로 여러 번 돌려도 결과가 같습니다(id·`updated_at`도 그대로).
- 저장된 `embedding_model`과 응답의 모델이 다르면 기존 벡터와 섞지 않고 그 문서의 청크를 전부 다시 넣습니다.
- 응답이 이상하면(차원·벡터 길이·빈 청크·중복 `chunk_id`·position 순서·날짜 형식) DB를 건드리지 않고 실패합니다.
  doc이 503을 돌려주면 doc에서 `rebuild_chunks.py`를 다시 돌린 뒤 동기화합니다.
- `chunk_id`에는 법령 번호가 들어 있어서, 법이 개정되면 그 문서의 청크가 모두 새로 들어가고 이전 청크는 지워집니다.

### 검색

`Documents::Search.new.call(question, limit: 5)`는 질문 벡터를 doc에서 받아 코사인 거리(`<=>`)로 가까운 청크를 찾습니다.

- 질문과 같은 임베딩 모델로 적재된 문서만 검색합니다. 맞는 문서가 하나도 없으면 `ModelMismatch`로 재동기화를 알립니다.
- 청크가 300여 개라 벡터 인덱스 없이 정확 검색합니다. 가이드 문서 등으로 수만 개가 되면 HNSW(`vector_cosine_ops`)를 추가합니다.
- 아직 시행 전인 조문(`is_effective=false`)도 결과에 넣고 `status: :pending`과 `effective_date`로 구분합니다.
  `effective_only: true`로 뺄 수 있습니다.
- 현행본과 미시행본의 같은 조각이 글자까지 같으면(예: 제75조) 미시행본을 빼고, 현행본에 `pending_amendment_date`를 붙입니다.
  같은 조번호에 미시행 개정본이 있는 현행 조문에는 모두 이 날짜가 붙습니다.

### 검색 평가

`config/evaluation/retrieval_eval_v1.json`(30문항: 일반 23, 과태료 7)으로 실제 검색 품질을 잽니다.
AI 답변을 붙이기 전에 검색이 맞는 조문을 찾는지 보는 기준선이고, 청킹·검색 규칙을 바꿀 때마다 다시 돌려 비교합니다.

```bash
docker exec privacy-genie-web bin/rails search:evaluate
docker exec privacy-genie-web bin/rails search:evaluate OUTPUT=tmp/search_eval.json   # 결과 JSON 저장
docker exec privacy-genie-web bin/rails search:evaluate MIN_RECALL=0.9                # 기준 미달이면 실패
```

- 적중 판정: 검색된 청크의 문서 종류·조번호가 정답 조문과 같으면 적중입니다(조각·occurrence 무시).
  정답이 여러 조문이면 하나만 맞아도 적중입니다.
- 지표: Recall@5(상위 5개 안에 정답이 있는 비율), MRR(정답 순위의 역수 평균, 적재된 청크 전체 순위 기준).
- 현행 적중률: 현행본이 있는 문항(F1~F7, G11, G22)은 상위 5개에 현행 청크가 있어야 적중입니다.
  G15(미시행 조문뿐)에서 "아직 시행 전"이라고 답하는지는 AI를 붙인 뒤 답변 평가에서 봅니다.
- 30문항이라 한 문항이 Recall@5로 3.3%p입니다. 1~2문항 차이는 잡음으로 봅니다.
- 실제 doc 서비스와 적재된 DB가 필요해서 CI에서는 돌리지 않습니다. 평가 로직 자체는 `test/services/documents/`의
  테스트가 검증합니다.

기준선(2026-11-02, KURE-v1, 법률 156·시행령 168청크):

| 지표 | 값 |
|---|---|
| 전체 Recall@5 / MRR | 0.967 / 0.873 |
| 일반 Recall@5 / MRR | 1.000 / 0.877 |
| 과태료 Recall@5 / MRR | 0.857 / 0.861 |
| 현행 적중률@5 | 0.889 |

놓친 문항은 F2("유출을 신고하지 않으면 어떤 제재") 하나로, 정답 법 제75조가 33위입니다. 상위에는 신고 의무 조문
(시행령 제40조, 법 제34조)이 나옵니다.

### 질문 확인 화면 (개발용)

개발 서버에서 `http://localhost:3000/search`를 열면 질문을 넣어 실제 검색 결과를 볼 수 있습니다. 순위·유사도·
조번호·조각·시행 상태(현행, 미시행 시행일, 개정 예정일)·원문을 보여 줍니다. 개발 도구라 운영 환경에는 라우트가 없습니다
(`Rails.env.local?`일 때만). 최종 화면은 AI 답변을 붙인 뒤 따로 설계합니다.

### LLM 호출

Claude, GPT 등을 같은 인터페이스로 부릅니다. provider별 차이(요청 형식, 시스템 프롬프트 위치, 종료 사유 이름,
에러 형식)는 `app/clients/llm/`의 어댑터 안에만 둡니다.

```ruby
response = Llm.provider.generate(          # 이름을 넘기면 다른 provider: Llm.provider("openai")
  messages: [ Llm::Message.user("질문") ],
  system: "법령에 근거해 답하세요",
  max_tokens: 1024
)
response.text           # 답변
response.stop_reason    # :end_turn, :max_tokens, :refusal, :other
response.input_tokens   # 토큰·지연시간(latency_ms)으로 provider를 비교할 수 있습니다
```

설정은 `config/llm.yml`이 `.env`에서 읽습니다.

| 변수 | 설명 |
|---|---|
| `LLM_PROVIDER` | 기본 provider. `anthropic`(기본값) 또는 `openai` |
| `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL` | 모델 기본값은 `claude-sonnet-5` |
| `OPENAI_API_KEY`, `OPENAI_MODEL` | 모델은 꼭 지정해야 합니다 |
| `ANTHROPIC_BASE_URL`, `OPENAI_BASE_URL` | 선택. 프록시나 OpenAI 호환 서버를 쓸 때 |

에러는 `Llm::Error` 하위 타입으로 통일합니다. `RateLimitError`·`ServiceUnavailableError`는 잠시 뒤 재시도하거나
다른 provider로 넘길 수 있고, `AuthenticationError`·`InvalidRequestError`·`ConfigurationError`는 재시도해도
소용없습니다. 재시도는 HTTP 클라이언트가 아니라 호출하는 쪽(Job 등)에서 정합니다.

새 provider는 `Llm::Base`를 상속해 요청·응답 변환만 구현하고 `Llm::PROVIDERS`에 등록합니다. 테스트에
`LlmProviderContract`를 include하면 공통 동작(에러 변환, 설정 검증, 응답 형식)을 같은 기준으로 검증합니다.

### 테스트

```bash
docker exec privacy-genie-web bin/rails db:test:prepare test
```

doc API는 `test/support/fake_doc_client.rb`로 대신하고, doc·LLM 클라이언트는 Faraday 테스트 어댑터로 검증합니다.
테스트에서 실제 LLM API는 부르지 않습니다.
DB는 pgvector 확장이 있어야 하므로 로컬과 CI 모두 `pgvector/pgvector:pg17` 이미지를 씁니다.
