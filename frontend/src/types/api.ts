export interface ApiErrorPayload {
  message: string;
  status: number;
  details?: unknown;
}

export interface QueryParameterSchema {
  name: string;
  type: 'string' | 'integer' | 'datetime' | 'nullable_datetime';
  required: boolean;
  default: unknown;
  description: string;
}

export interface QueryCatalogItem {
  queryId: string;
  title: string;
  description: string;
  cypher: string;
  parameters: QueryParameterSchema[];
  expectedOperators: string[];
  defaultParams: Record<string, unknown>;
  presentation: string;
}

export interface QueryExecutionRequest { parameters: Record<string, unknown>; }
export interface QueryExecutionResponse {
  queryId: string;
  columns: string[];
  rows: Record<string, unknown>[];
  graph?: Record<string, unknown> | null;
  executionMs: number;
  expectedOperators: string[];
}
