# Architectural Specification Document (02_ARCHITECTURE.md) — Boulder Co-Setter App

**Versión:** 1.0.0  
**Estado:** ESPECIFICACIÓN TÉCNICA BASE (CLIENT-SERVER)  
**Enfoque:** SDD / Centralized Storage / PostgreSQL & S3 Cloud  

---

## 2. Arquitectura General del Sistema (Client-Server Pura)

```text
┌──────────────────────────────────────────────────────────────────────────────────┐
│                             DISPOSITIVO MÓVIL (Cliente)                          │
│                                                                                  │
│   ┌────────────────────────┐      ┌─────────────────────────┐                   │
│   │ UI Presentation Layer  │ ───> │ Canvas 2D Editor (RAM)  │                   │
│   └───────────┬────────────┘      └────────────┬────────────┘                   │
│               │                                │                                │
│               ▼                                ▼                                │
│   ┌────────────────────────┐      ┌─────────────────────────┐                   │
│   │ CV Engine (YOLO/OpenCV)│      │ HTTP/REST API Client    │                   │
│   │ (Segmentación en RAM)  │      │ (Retrofit / Dio / Fetch)│                   │
│   └────────────────────────┘      └────────────┬────────────┘                   │
└────────────────────────────────────────────────┼─────────────────────────────────┘
                                                 │ HTTPS / Multipart Data
                                                 ▼
┌──────────────────────────────────────────────────────────────────────────────────┐
│                               NUBE / BACKEND API                                 │
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────┐                    │
│   │              API Gateway / Business Logic               │                    │
│   └───────────┬─────────────────────────────────┬───────────┘                    │
│               │                                 │                                │
│               ▼                                 ▼                                │
│   ┌────────────────────────┐      ┌─────────────────────────┐                    │
│   │   PostgreSQL Database  │      │  Object Storage         │                    │
│   │  (Metadatos & Rutas)   │      │  (PNG Sprites & Photos) │                    │
│   └────────────────────────┘      └─────────────────────────┘                    │
└──────────────────────────────────────────────────────────────────────────────────┘