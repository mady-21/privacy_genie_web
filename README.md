## privacy-genie-web

`privacy-genie-web`은 사용자의 개인정보보호 관련 질문을 받아 **문서 검색부터 LLM 답변 생성까지 전체 서비스 흐름을 제어하는 Rails 기반 웹 애플리케이션**으로
문서 처리 및 검색은 별도의 `privacy-genie-doc` 서비스에 요청하고, 반환된 관련 문서를 사용자 질문과 함께 LLM에 전달하여 최종 답변을 생성합니다.

### 처리 흐름

```text
사용자 질문
    │
    ▼
Rails
    │
    ▼
privacy-genie-doc 검색 요청
    │
    ▼
관련 Chunk 반환
    │
    ▼
질문 + 관련 Chunk
    │
    ▼
LLM
    │
    ▼
근거 기반 답변 생성
    │
    ▼
사용자에게 답변
```

또한 문서 등록 및 관리가 필요한 경우 `privacy-genie-doc`과 연동하여 문서 처리 작업을 요청하고, 처리 결과와 문서 정보를 관리합니다.

```text
문서 등록
    │
    ▼
Rails
    │
    ▼
privacy-genie-doc
    │
    ▼
Parsing / Chunking / Embedding
    │
    ▼
처리 결과 관리
```

즉, **사용자와 직접 상호작용하고, 문서 검색 서비스와 LLM을 연결하여 개인정보보호 관련 질의응답 서비스를 제공하는 역할**을 담당합니다.

문서 Parsing, 구조 분석, Chunking, Embedding 및 Vector Search는 별도의 Python 서비스인 [privacy-genie-doc](https://github.com/mady-21/privacy_genie_doc)에서 담당합니다.
