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

### 테스트

```bash
docker exec privacy-genie-web bin/rails db:test:prepare test
```

doc API는 `test/support/fake_doc_client.rb`로 대신하고, 클라이언트는 Faraday 테스트 어댑터로 검증합니다.
DB는 pgvector 확장이 있어야 하므로 로컬과 CI 모두 `pgvector/pgvector:pg17` 이미지를 씁니다.
