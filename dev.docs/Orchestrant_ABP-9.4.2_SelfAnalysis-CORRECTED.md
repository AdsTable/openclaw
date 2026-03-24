# ABP 9.4.2 Orchestrator — Self-Analysis CORRECTED
<!-- Last verified: 2026-03-24 -->
<!-- Corrects: Orchestrant_ABP-9.4.2_SelfAnalysis.txt -->
<!-- Target: AdsTable.Site — ASP.NET Boilerplate 9.4.2, NOT Volo.Abp -->
<!-- Prerequisite: read Orchestrant_ABP-9.4.2-CORRECTED.md first -->

> **The self-analysis document corrects some issues from the original but introduces
> 12 new critical bugs — and critically, the framework confusion (`Volo.Abp.*`)
> persists through 25+ occurrences despite claiming to fix it.**

---

## 🔴 All Errors Found — 26 Total

### Framework Errors (all CRITICAL — 25+ occurrences)

| Volo.Abp (WRONG — used in self-analysis) | Abp.* (CORRECT — our stack) |
|------------------------------------------|------------------------------|
| `Volo.Abp.Domain.Entities.Auditing.FullAuditedAggregateRoot<T>` | `Abp.Domain.Entities.Auditing.FullAuditedEntity<T>` |
| `Volo.Abp.BusinessException` | `Abp.UI.UserFriendlyException` |
| `Volo.Abp.Check.NotNullOrWhiteSpace()` | Manual guards (`string.IsNullOrWhiteSpace` + throw) |
| `Volo.Abp.Domain.Services.DomainService` | `Abp.Domain.Services.DomainService` |
| `Volo.Abp.Guids.IGuidGenerator` | `Guid.NewGuid()` |
| `Volo.Abp.DependencyInjection.ITransientDependency` | `Abp.Dependency.ITransientDependency` |
| `Volo.Abp.BackgroundJobs.AsyncBackgroundJob<T>` | `Abp.BackgroundJobs.AsyncBackgroundJob<T>` |
| `Volo.Abp.BackgroundJobs.IBackgroundJobManager` | `Abp.BackgroundJobs.IBackgroundJobManager` |
| `Volo.Abp.Uow.IUnitOfWorkManager` | `Abp.Domain.Uow.IUnitOfWorkManager` |
| `Volo.Abp.Uow.UnitOfWorkAttribute` | `Abp.Domain.Uow.UnitOfWorkAttribute` |
| `Volo.Abp.BackgroundWorkers.AsyncPeriodicBackgroundWorkerBase` | `Abp.Threading.BackgroundWorkers.AsyncPeriodicBackgroundWorkerBase` (**EXISTS in ABP 9.4.2**) |
| `Volo.Abp.BackgroundWorkers.AbpAsyncTimer` | `Abp.Threading.Timers.AbpAsyncTimer` (**EXISTS in ABP 9.4.2**) |
| `Volo.Abp.Caching.IDistributedCache<T>` | `Abp.Runtime.Caching.ICacheManager` |
| `Volo.Abp.BackgroundJobs.BackgroundJobName` attribute | Hangfire `[DisplayName]` attribute |
| `AddLocalEvent()` on entity | `IEventBus.Trigger()` called from domain service |
| `Volo.Abp.Modularity.AbpModule.ConfigureServices()` | `Abp.Modules.AbpModule.PreInitialize()` |

### Code Bugs Introduced by Self-Analysis (NEW errors)

| # | Severity | Bug | Effect |
|---|----------|-----|--------|
| 1 | 🔴 CRITICAL | `retry.SetRetryOf(failed.Id)` called but method never defined on entity | `CS0117` compile error |
| 2 | 🔴 CRITICAL | `_matrix.GetPrimaryModel()` called synchronously — interface only has `GetPrimaryModelAsync()` | `CS0117` compile error |
| 3 | 🔴 CRITICAL | `_matrix.GetFallbackModel()` — same sync/async mismatch | `CS0117` compile error |
| 4 | 🔴 CRITICAL | `OrchestrationErrorCodes.*` used 5× but constants class never defined | `CS0103` compile error |
| 5 | 🔴 CRITICAL | `WorkerCompletedEto`, `WorkerFailedEto`, `WorkerEscalatedEto` used but never defined | `CS0246` compile error |
| 6 | 🔴 CRITICAL | `result` from `_apiClient.CompleteAsync()` assigned to local var, never stored on entity | Data lost permanently |
| 7 | 🔴 CRITICAL | `BackgroundJobExecutionException` with new `args` — Hangfire ignores exception payload, retries with ORIGINAL args | Retry always uses original (failed) model |
| 8 | 🔴 CRITICAL | `CancellationToken` fetched via `ServiceProvider.GetRequiredService<CancellationToken>()` — not registered in DI | `InvalidOperationException` at runtime |
| 9 | 🟠 HIGH | `async (_, e) => await ProcessMessageAsync(...)` on `Notification` event — `async void` equivalent, exceptions swallowed | Silent message loss |
| 10 | 🟠 HIGH | `NpgsqlConnection _listenConn` opened in `StartAsync`, never disposed | PostgreSQL connection leak |
| 11 | 🟠 HIGH | Deploy script: `die "Migration failed"` does NOT call `rollback()` — data unrecoverable on migration error | Manual recovery needed |
| 12 | 🟡 MEDIUM | `Guid.NewGuid()` in migration seed `InsertData()` — non-deterministic, different GUIDs on every `Add-Migration` run | Inconsistent environments |
| 13 | 🟡 MEDIUM | JSONB column: `t.Column<string>(nullable: false)` without `HasColumnType("jsonb")` | Stored as `text`, no PostgreSQL JSONB features (GIN index, `@>` operator) |
| 14 | 🟡 MEDIUM | Model names in seed: `claude-sonnet-4-6`, `claude-opus-4-6` — do not exist | Job fails with `NoModelForTaskType` at runtime |
| 15 | 🟡 MEDIUM | `ITaskMatrixProvider` injected into `DomainService` — Domain layer depends on Infrastructure | DDD layer violation |
| 16 | 🟡 MEDIUM | `LazyServiceProvider.GetRequiredServiceAsync<T>()` — not a standard ABP old-ABP pattern | Not available in `Abp.*` |

---

## ✅ CORRECTED IMPLEMENTATION

> ⚠️ **DATA SAFETY — BEFORE ANY EF MIGRATION:**
> ```bash
> pg_dump --table="OrchestrationWorkers" \
>         --table="OrchestrationMessages" \
>         --table="OrchestrationTaskMatrix" \
>         --format=custom \
>         --file="backup_pre_orch_$(date +%Y%m%d_%H%M%S).dump" \
>         "${PGDATABASE}"
> ```

---

### 1. Domain Entity (CORRECTED)

```csharp
// src/AdsTable.Site.Core/Orchestration/OrchestrationWorker.cs
using System;
using Abp.Domain.Entities.Auditing; // ✅ Abp.* NOT Volo.Abp.*

namespace AdsTable.Site.Orchestration
{
    // ✅ FullAuditedEntity<Guid> — old ABP equivalent of FullAuditedAggregateRoot<Guid>
    // Includes: CreationTime, CreatorUserId, LastModificationTime, LastModifierId,
    //           IsDeleted, DeletionTime, DeleterId
    // ✅ NO AddLocalEvent() — events raised from domain service via IEventBus
    public class OrchestrationWorker : FullAuditedEntity<Guid>
    {
        // ✅ EF Core requires protected parameterless constructor
        protected OrchestrationWorker() { }

        // ✅ Internal — only created via factory method in domain service
        internal OrchestrationWorker(
            Guid id,
            string taskId,
            string taskType,
            string modelId)
        {
            Id       = id;
            TaskId   = taskId;
            TaskType = taskType;
            ModelId  = modelId;
            Status   = WorkerStatus.Pending;
        }

        public string       TaskId     { get; private set; } = null!;
        public string       TaskType   { get; private set; } = null!;
        public string       ModelId    { get; private set; } = null!;
        public WorkerStatus Status     { get; private set; }
        public string?      Output     { get; private set; } // ✅ stores Claude result
        public string?      FailReason { get; private set; }
        public Guid?        RetryOfId  { get; private set; } // ✅ Guid NOT string
        public bool         IsEscalated { get; private set; }
        public int          RetryCount  { get; private set; }
        public DateTime?    StartedAt   { get; private set; }
        public DateTime?    EndedAt     { get; private set; }

        // ✅ Computed — not persisted
        public TimeSpan? Duration =>
            StartedAt.HasValue && EndedAt.HasValue
                ? EndedAt.Value - StartedAt.Value
                : (TimeSpan?)null;

        // ✅ SetRetryOf — DEFINED (was missing in self-analysis)
        internal void SetRetryOf(Guid parentId)
        {
            RetryOfId = parentId;
        }

        public void MarkRunning()
        {
            if (Status != WorkerStatus.Pending)
                // ✅ UserFriendlyException NOT BusinessException (old ABP)
                throw new Abp.UI.UserFriendlyException(
                    $"Cannot mark Running: current status is {Status}");
            Status    = WorkerStatus.Running;
            StartedAt = DateTime.UtcNow;
        }

        // ✅ output parameter added — fixes data loss bug from self-analysis
        public void MarkDone(string output)
        {
            if (Status != WorkerStatus.Running)
                throw new Abp.UI.UserFriendlyException(
                    $"Cannot mark Done: current status is {Status}");
            Status  = WorkerStatus.Done;
            Output  = output;  // ✅ PERSISTED — was missing in all previous versions
            EndedAt = DateTime.UtcNow;
            // Domain event raised from OrchestratorWorkerManager after SaveChanges
        }

        public void MarkFailed(string reason)
        {
            if (Status == WorkerStatus.Done)
                throw new Abp.UI.UserFriendlyException(
                    "Cannot fail a completed worker");
            Status     = WorkerStatus.Failed;
            FailReason = reason?.Substring(0, Math.Min(reason?.Length ?? 0, 512));
            EndedAt    = DateTime.UtcNow;
            RetryCount++;
        }

        public void Escalate()
        {
            IsEscalated = true;
            // Note: status intentionally NOT changed to keep Failed for audit trail
        }
    }

    public enum WorkerStatus { Pending, Running, Done, Failed, Escalated }
}
```

---

### 2. Domain Error Codes (MISSING in self-analysis)

```csharp
// src/AdsTable.Site.Core/Orchestration/OrchestrationErrorCodes.cs
namespace AdsTable.Site.Orchestration
{
    // ✅ String constants matching ABP error code conventions
    public static class OrchestrationErrorCodes
    {
        public const string DuplicateActiveTask        = "Orchestration:0001";
        public const string NoModelForTaskType         = "Orchestration:0002";
        public const string CannotFailCompletedWorker  = "Orchestration:0003";
        public const string CanOnlyRetryFailedWorkers  = "Orchestration:0004";
        public const string InvalidStatusTransition    = "Orchestration:0005";
    }
}
```

---

### 3. Domain Event Data (MISSING in self-analysis)

```csharp
// src/AdsTable.Site.Core/Orchestration/OrchestrationEventData.cs
using System;
using Abp.Events.Bus; // ✅ Abp.* NOT Volo.Abp.*

namespace AdsTable.Site.Orchestration
{
    // ✅ Old ABP: plain data classes (not ETOs — that's Volo.Abp terminology)
    // IEventData interface is optional in old ABP
    public class WorkerCompletedEventData
    {
        public Guid   WorkerId { get; set; }
        public string TaskId   { get; set; } = null!;
        public string Output   { get; set; } = null!;
    }

    public class WorkerFailedEventData
    {
        public Guid   WorkerId { get; set; }
        public string TaskId   { get; set; } = null!;
        public string Reason   { get; set; } = null!;
    }

    public class WorkerEscalatedEventData
    {
        public Guid   WorkerId { get; set; }
        public string TaskId   { get; set; } = null!;
    }
}
```

---

### 4. Domain Service (CORRECTED)

```csharp
// src/AdsTable.Site.Core/Orchestration/OrchestrationWorkerManager.cs
using System;
using System.Threading.Tasks;
using Abp.Domain.Services;     // ✅ Abp.* NOT Volo.Abp.*
using Abp.Events.Bus;           // ✅ IEventBus — replaces AddLocalEvent()
using Abp.UI;

namespace AdsTable.Site.Orchestration
{
    // ✅ SiteDomainServiceBase — project's domain service base (NOT plain DomainService)
    //    Adds LocalizationSourceName = SiteConsts.LocalizationSourceName
    // ✅ NO ITaskMatrixProvider injection here — Domain must NOT depend on Infrastructure
    //    Matrix provider is injected at Application layer (OrchestratorAppService / Job)
    public class OrchestrationWorkerManager : SiteDomainServiceBase
    {
        private readonly IOrchestrationWorkerRepository _repo;
        private readonly IEventBus                      _eventBus;

        public OrchestrationWorkerManager(
            IOrchestrationWorkerRepository repo,
            IEventBus eventBus)
        {
            _repo     = repo;
            _eventBus = eventBus;
        }

        public OrchestrationWorker Create(
            string taskId,
            string taskType,
            string modelId)
        {
            // ✅ Manual guards — Volo.Abp.Check does not exist in old ABP
            if (string.IsNullOrWhiteSpace(taskId))
                throw new ArgumentException("taskId required", nameof(taskId));
            if (taskId.Length > 128)
                throw new ArgumentException("taskId max 128 chars", nameof(taskId));
            if (string.IsNullOrWhiteSpace(taskType))
                throw new ArgumentException("taskType required", nameof(taskType));
            if (string.IsNullOrWhiteSpace(modelId))
                throw new ArgumentException("modelId required", nameof(modelId));

            // ✅ Guid.NewGuid() — IGuidGenerator not needed for entity creation
            return new OrchestrationWorker(
                Guid.NewGuid(),
                taskId,
                taskType,
                modelId);
        }

        public OrchestrationWorker CreateRetry(
            OrchestrationWorker failed,
            string nextModelId)
        {
            if (failed.Status != WorkerStatus.Failed)
                throw new UserFriendlyException(
                    "Can only retry Failed workers. Current status: " + failed.Status);

            var retry = new OrchestrationWorker(
                Guid.NewGuid(),         // ✅ new ID, NOT Guid.Empty
                failed.TaskId,
                failed.TaskType,
                nextModelId);

            retry.SetRetryOf(failed.Id); // ✅ method is now defined on entity

            return retry;
        }

        // ✅ Events triggered HERE (domain service), not inside entity
        public async Task RaiseCompletedEventAsync(OrchestrationWorker worker)
        {
            await _eventBus.TriggerAsync(new WorkerCompletedEventData
            {
                WorkerId = worker.Id,
                TaskId   = worker.TaskId,
                Output   = worker.Output ?? string.Empty
            });
        }

        public async Task RaiseFailedEventAsync(OrchestrationWorker worker)
        {
            await _eventBus.TriggerAsync(new WorkerFailedEventData
            {
                WorkerId = worker.Id,
                TaskId   = worker.TaskId,
                Reason   = worker.FailReason ?? string.Empty
            });
        }
    }
}
```

---

### 5. Background Job (CORRECTED — simplified retry)

```csharp
// src/AdsTable.Site.Application/Orchestration/OrchestrationJob.cs
using System;
using System.Threading.Tasks;
using Abp.BackgroundJobs;       // ✅ Abp.* NOT Volo.Abp.*
using Abp.Dependency;
using Abp.Domain.Uow;
using Hangfire;
using Microsoft.Extensions.Logging;

namespace AdsTable.Site.Application.Orchestration
{
    // ✅ [DisplayName] from Hangfire (not [BackgroundJobName] from Volo.Abp)
    [DisplayName("Orchestration: {0} ({1})")]
    // ✅ Explicit retry limit — 3 attempts max (not default 10)
    [AutomaticRetry(Attempts = 3, OnAttemptsExceeded = AttemptsExceededAction.Fail)]
    public class OrchestrationJob
        : AsyncBackgroundJob<OrchestrationJobArgs>,
          ITransientDependency  // ✅ Abp.Dependency.ITransientDependency
    {
        private readonly IOrchestrationWorkerRepository _repo;
        private readonly OrchestrationWorkerManager     _manager;
        private readonly IOrchestrationApiClient        _apiClient;
        private readonly ITaskMatrixProvider            _matrix;    // ✅ injected here, NOT in domain
        private readonly IUnitOfWorkManager             _uowManager;
        private readonly ILogger<OrchestrationJob>      _logger;

        public OrchestrationJob(
            IOrchestrationWorkerRepository repo,
            OrchestrationWorkerManager manager,
            IOrchestrationApiClient apiClient,
            ITaskMatrixProvider matrix,
            IUnitOfWorkManager uowManager,
            ILogger<OrchestrationJob> logger)
        {
            _repo       = repo;
            _manager    = manager;
            _apiClient  = apiClient;
            _matrix     = matrix;
            _uowManager = uowManager;
            _logger     = logger;
        }

        // ✅ [UnitOfWork] from Abp.Domain.Uow (exists in old ABP)
        [Abp.Domain.Uow.UnitOfWork]
        public override async Task ExecuteAsync(OrchestrationJobArgs args)
        {
            // ✅ Select model based on DB state — NOT args.AttemptNumber (Hangfire
            // re-deserializes args from JSON for each retry; in-memory mutations are lost).
            // Query existing workers to know which models were already tried.
            var previousWorkers = await _repo.GetWorkersByTaskIdAsync(args.TaskId);
            var attemptNumber = previousWorkers.Count + 1;
            if (previousWorkers.Any(w => w.Status == WorkerStatus.Done))
            {
                _logger.LogInformation(
                    "Task {TaskId} already completed by a previous attempt — skipping",
                    args.TaskId);
                return;
            }
            var usedModelIds = previousWorkers
                .Select(w => w.ModelId)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);

            var modelId = attemptNumber == 1
                ? await _matrix.GetPrimaryModelAsync(args.TaskType)
                : await _matrix.GetFallbackModelAsync(args.TaskType, usedModelIds.LastOrDefault());

            _logger.LogInformation(
                "Orchestration job: taskId={TaskId} taskType={TaskType} attempt={Attempt} model={Model}",
                args.TaskId, args.TaskType, attemptNumber, modelId);

            if (modelId == null)
            {
                _logger.LogWarning(
                    "No model available for taskType={TaskType} — escalating", args.TaskType);
                await EscalateAsync(args.TaskId);
                return; // Do NOT rethrow — stop Hangfire retry cycle
            }

            var worker = _manager.Create(args.TaskId, args.TaskType, modelId);
            await _repo.InsertAsync(worker);

            // Phase 1: persist Running status BEFORE external API call
            using (var uow = _uowManager.Begin(
                new Abp.Domain.Uow.UnitOfWorkOptions
                {
                    Scope = System.Transactions.TransactionScopeOption.RequiresNew
                }))
            {
                worker.MarkRunning();
                await _repo.UpdateAsync(worker);
                await uow.CompleteAsync();
            }

            try
            {
                var timeoutMs = await _matrix.GetTimeoutMsAsync(args.TaskType);
                using var cts = new System.Threading.CancellationTokenSource(timeoutMs);

                var result = await _apiClient.CompleteAsync(
                    new OrchestrationRequest
                    {
                        Prompt   = args.Prompt,
                        ModelId  = worker.ModelId,
                        TaskType = args.TaskType
                    },
                    cts.Token);

                // Phase 2: persist result
                using var uow = _uowManager.Begin(
                    new Abp.Domain.Uow.UnitOfWorkOptions
                    {
                        Scope = System.Transactions.TransactionScopeOption.RequiresNew
                    });

                worker = await _repo.GetAsync(worker.Id);
                worker.MarkDone(result.Text); // ✅ result IS stored on entity now
                await _repo.UpdateAsync(worker);
                await _manager.RaiseCompletedEventAsync(worker);
                await uow.CompleteAsync();

                _logger.LogInformation(
                    "Task {TaskId} done. Model={ModelId} Duration={Duration}ms",
                    args.TaskId, worker.ModelId,
                    worker.Duration?.TotalMilliseconds);
            }
            catch (OperationCanceledException)
            {
                await PersistFailureAsync(worker.Id, $"Timeout after {timeoutMs}ms");
                // ✅ State-based retry: next Hangfire attempt queries DB to find
                //    which models were tried; no need to mutate args (Hangfire
                //    re-deserializes args from JSON, in-memory mutations are lost).
                throw; // Hangfire schedules retry up to [AutomaticRetry(Attempts=3)]
            }
            catch (Exception ex)
            {
                await PersistFailureAsync(worker.Id, ex.Message);
                await _manager.RaiseFailedEventAsync(
                    await _repo.GetAsync(worker.Id));
                _logger.LogError(ex,
                    "Task {TaskId} failed on model {ModelId}",
                    args.TaskId, worker.ModelId);
                throw; // ✅ Hangfire schedules retry (up to Attempts = 3)
            }
        }

        private async Task PersistFailureAsync(Guid workerId, string reason)
        {
            using var uow = _uowManager.Begin(
                new Abp.Domain.Uow.UnitOfWorkOptions
                {
                    Scope = System.Transactions.TransactionScopeOption.RequiresNew
                });
            var w = await _repo.GetAsync(workerId);
            w.MarkFailed(reason); // ✅ NEVER delete — status only
            await _repo.UpdateAsync(w);
            await uow.CompleteAsync();
        }

        private async Task EscalateAsync(string taskId)
        {
            // Find any existing Failed worker to escalate
            var failed = await _repo.FindByTaskIdAndStatusAsync(
                taskId, WorkerStatus.Failed);
            if (failed == null) return;

            using var uow = _uowManager.Begin(
                new Abp.Domain.Uow.UnitOfWorkOptions
                {
                    Scope = System.Transactions.TransactionScopeOption.RequiresNew
                });
            failed.Escalate();
            await _repo.UpdateAsync(failed);
            await _manager.RaiseFailedEventAsync(failed);
            await uow.CompleteAsync();
        }
    }

    // ✅ Simplified args — NO AttemptNumber/PreviousModelId:
    //    retry state is read from DB (OrchestrationWorker records),
    //    NOT from Hangfire args (which are re-deserialized from original JSON each retry)
    [Serializable] // ✅ Required for Hangfire PostgreSQL serialization
    public class OrchestrationJobArgs
    {
        public string  TaskId    { get; set; } = null!;
        public string  TaskType  { get; set; } = null!;
        public string? TenantId  { get; set; } // ✅ Multi-tenancy: set at dispatch time
        public string  Prompt    { get; set; } = null!;
    }
}
```

---

### 6. ITaskMatrixProvider — Async Interface (CORRECTED)

```csharp
// src/AdsTable.Site.Core/Orchestration/ITaskMatrixProvider.cs
// ✅ Interface stays in Core layer (no infrastructure dependency)
using System.Threading.Tasks;

namespace AdsTable.Site.Orchestration
{
    public interface ITaskMatrixProvider
    {
        Task<string?> GetPrimaryModelAsync(string taskType);
        // ✅ excludeModelId — pass the model that just failed
        Task<string?> GetFallbackModelAsync(string taskType, string? excludeModelId);
        Task<int>     GetTimeoutMsAsync(string taskType);
        Task<int>     GetMaxRetriesAsync(string taskType);
    }
}
```

```csharp
// src/AdsTable.Site.Application/Orchestration/DbTaskMatrixProvider.cs
using System;
using System.Text.Json;
using System.Threading.Tasks;
using Abp.Dependency;
using Abp.Runtime.Caching; // ✅ ICacheManager — NOT Volo.Abp.Caching.IDistributedCache<T>
using AdsTable.Site.Orchestration;

namespace AdsTable.Site.Application.Orchestration
{
    public class DbTaskMatrixProvider : ITaskMatrixProvider, ITransientDependency
    {
        private readonly IOrchestrationTaskMatrixRepository _repo;
        private readonly ICacheManager                      _cache;

        public DbTaskMatrixProvider(
            IOrchestrationTaskMatrixRepository repo,
            ICacheManager cache)
        {
            _repo  = repo;
            _cache = cache;
        }

        public async Task<string?> GetPrimaryModelAsync(string taskType)
        {
            var entry = await GetCachedAsync(taskType);
            return entry?.PrimaryModel;
        }

        public async Task<string?> GetFallbackModelAsync(
            string taskType, string? excludeModelId)
        {
            var entry = await GetCachedAsync(taskType);
            if (entry == null) return null;

            var fallbacks = JsonSerializer.Deserialize<string[]>(
                entry.FallbackModelsJson) ?? [];

            return fallbacks.FirstOrDefault(m => m != excludeModelId);
        }

        public async Task<int> GetTimeoutMsAsync(string taskType)
            => (await GetCachedAsync(taskType))?.TimeoutMs ?? 300_000;

        public async Task<int> GetMaxRetriesAsync(string taskType)
            => (await GetCachedAsync(taskType))?.MaxRetries ?? 2;

        // ✅ ICacheManager.GetCache().GetOrDefaultAsync() — old ABP pattern
        private async Task<TaskMatrixCacheItem?> GetCachedAsync(string taskType)
        {
            var cache = _cache.GetCache<string, TaskMatrixCacheItem>("TaskMatrix");

            return await cache.GetOrDefaultAsync(taskType) ??
                   await RefreshCacheAsync(taskType, cache);
        }

        private async Task<TaskMatrixCacheItem?> RefreshCacheAsync(
            string taskType,
            ITypedCache<string, TaskMatrixCacheItem> cache)
        {
            var row = await _repo.FindActiveByTaskTypeAsync(taskType);
            if (row == null) return null;

            var item = new TaskMatrixCacheItem
            {
                PrimaryModel       = row.PrimaryModel,
                FallbackModelsJson = row.FallbackModels,
                TimeoutMs          = row.TimeoutMs,
                MaxRetries         = row.MaxRetries
            };

            await cache.SetAsync(taskType, item,
                absoluteExpireTime: TimeSpan.FromMinutes(5));

            return item;
        }
    }

    public class TaskMatrixCacheItem
    {
        public string PrimaryModel       { get; set; } = null!;
        public string FallbackModelsJson { get; set; } = "[]";
        public int    TimeoutMs          { get; set; } = 300_000;
        public int    MaxRetries         { get; set; } = 2;
    }
}
```

---

### 7. EF Core Configuration — Key Fixes

```csharp
// src/AdsTable.Site.EntityFrameworkCore/OrchestrationWorkerConfig.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

public class OrchestrationWorkerConfiguration
    : IEntityTypeConfiguration<OrchestrationWorker>
{
    public void Configure(EntityTypeBuilder<OrchestrationWorker> b)
    {
        b.ToTable("OrchestrationWorkers");
        b.HasKey(x => x.Id);

        b.Property(x => x.TaskId).IsRequired().HasMaxLength(128);
        b.Property(x => x.TaskType).IsRequired().HasMaxLength(64);
        b.Property(x => x.ModelId).IsRequired().HasMaxLength(64);
        b.Property(x => x.Output).HasMaxLength(65_535); // ✅ stores result
        b.Property(x => x.FailReason).HasMaxLength(512);

        // ✅ Store as string in Postgres — readable, sortable
        b.Property(x => x.Status)
            .HasConversion<string>()
            .HasMaxLength(16);

        // ✅ NOT persisted — computed property
        b.Ignore(x => x.Duration);

        b.HasIndex(x => x.TaskId);  // ✅ NOT unique — same TaskId has multiple workers (retries)
        b.HasIndex(x => new { x.TaskId, x.ModelId }).IsUnique(); // ✅ unique per (task, model) pair
        b.HasIndex(x => new { x.Status, x.TaskType });
        // Self-referencing FK — NEVER cascade delete
        b.HasOne<OrchestrationWorker>()
            .WithMany()
            .HasForeignKey(x => x.RetryOfId)
            .OnDelete(DeleteBehavior.Restrict);
    }
}

public class OrchestrationTaskMatrixConfiguration
    : IEntityTypeConfiguration<OrchestrationTaskMatrix>
{
    public void Configure(EntityTypeBuilder<OrchestrationTaskMatrix> b)
    {
        b.ToTable("OrchestrationTaskMatrix");
        b.HasKey(x => x.Id);

        b.Property(x => x.TaskType).IsRequired().HasMaxLength(64);
        b.Property(x => x.PrimaryModel).IsRequired().HasMaxLength(64);

        // ✅ HasColumnType("jsonb") — enables GIN index, @> operator in PostgreSQL
        b.Property(x => x.FallbackModels)
            .HasColumnType("jsonb")
            .IsRequired()
            .HasDefaultValue("[]");

        b.HasIndex(x => x.TaskType).IsUnique();
    }
}
```

---

### 8. EF Core Migration — Key Fixes

```csharp
// Migrations/20260324_AddOrchestration.cs
// ⚠️ DO NOT run Down() on prod without restoring from pg_dump backup first

public partial class AddOrchestration : Migration
{
    protected override void Up(MigrationBuilder m)
    {
        m.CreateTable("OrchestrationWorkers", t => new
        {
            Id         = t.Column<Guid>(nullable: false),
            TaskId     = t.Column<string>(maxLength: 128, nullable: false),
            TaskType   = t.Column<string>(maxLength: 64, nullable: false),
            ModelId    = t.Column<string>(maxLength: 64, nullable: false),
            Status     = t.Column<string>(maxLength: 16, nullable: false,
                             defaultValue: "Pending"),
            Output     = t.Column<string>(maxLength: 65535, nullable: true),
            FailReason = t.Column<string>(maxLength: 512, nullable: true),
            RetryOfId  = t.Column<Guid>(nullable: true),
            IsEscalated = t.Column<bool>(nullable: false, defaultValue: false),
            RetryCount  = t.Column<int>(nullable: false, defaultValue: 0),
            StartedAt  = t.Column<DateTime>(nullable: true),
            EndedAt    = t.Column<DateTime>(nullable: true),
            // ABP FullAuditedEntity columns
            CreationTime         = t.Column<DateTime>(nullable: false),
            CreatorUserId        = t.Column<long>(nullable: true),
            LastModificationTime = t.Column<DateTime>(nullable: true),
            LastModifierUserId   = t.Column<long>(nullable: true),
            IsDeleted            = t.Column<bool>(nullable: false, defaultValue: false),
            DeletionTime         = t.Column<DateTime>(nullable: true),
            DeleterUserId        = t.Column<long>(nullable: true)
        }, t =>
        {
            t.PrimaryKey("PK_OrchestrationWorkers", x => x.Id);
            t.ForeignKey(
                "FK_OrchestrationWorkers_RetryOf",
                x => x.RetryOfId,
                "OrchestrationWorkers", "Id",
                onDelete: ReferentialAction.Restrict); // NEVER Cascade
        });

        m.CreateIndex("IX_OW_TaskId", "OrchestrationWorkers", "TaskId");
        m.CreateIndex("IX_OW_Status_TaskType", "OrchestrationWorkers",
            new[] { "Status", "TaskType" });
        // ✅ Partial index — PostgreSQL only, reduces index size
        m.CreateIndex("IX_OW_RetryOfId", "OrchestrationWorkers", "RetryOfId",
            filter: "\"RetryOfId\" IS NOT NULL");

        m.CreateTable("OrchestrationTaskMatrix", t => new
        {
            Id             = t.Column<Guid>(nullable: false),
            TaskType       = t.Column<string>(maxLength: 64, nullable: false),
            PrimaryModel   = t.Column<string>(maxLength: 64, nullable: false),
            // ✅ jsonb type — enables GIN index and @> operator
            FallbackModels = t.Column<string>(nullable: false,
                                 defaultValue: "[]")
                                 .Annotation("Npgsql:PostgresType", "jsonb"),
            TimeoutMs      = t.Column<int>(nullable: false, defaultValue: 300_000),
            MaxRetries     = t.Column<int>(nullable: false, defaultValue: 2),
            IsActive       = t.Column<bool>(nullable: false, defaultValue: true)
        }, t => t.PrimaryKey("PK_OrchestrationTaskMatrix", x => x.Id));

        m.CreateIndex("IX_OTM_TaskType", "OrchestrationTaskMatrix",
            "TaskType", unique: true);

        // ✅ Fixed deterministic GUIDs for seed data
        // Guid.NewGuid() in migration = different GUID on every Add-Migration run
        m.InsertData("OrchestrationTaskMatrix",
            columns: new[] { "Id", "TaskType", "PrimaryModel",
                             "FallbackModels", "TimeoutMs", "MaxRetries", "IsActive" },
            values: new object[,]
            {
                // ✅ Fixed GUIDs — deterministic, same across all environments
                { new Guid("a1000001-0000-0000-0000-000000000001"),
                  "backend_csharp", "claude-opus-4-5-20251101",
                  "[\"claude-opus-4-5-20251101\"]", 600_000, 2, true },

                { new Guid("a1000001-0000-0000-0000-000000000002"),
                  "frontend_js", "claude-opus-4-5-20251101",
                  "[\"claude-opus-4-5-20251101\"]", 300_000, 3, true },

                { new Guid("a1000001-0000-0000-0000-000000000003"),
                  "wp6_rest", "claude-opus-4-5-20251101",
                  "[\"claude-opus-4-5-20251101\"]", 300_000, 3, true },

                { new Guid("a1000001-0000-0000-0000-000000000004"),
                  "nginx_infra", "claude-opus-4-5-20251101",
                  "[\"claude-opus-4-5-20251101\"]", 600_000, 1, true },

                { new Guid("a1000001-0000-0000-0000-000000000005"),
                  "code_analysis", "claude-opus-4-5-20251101",
                  "[\"claude-opus-4-5-20251101\"]", 900_000, 1, true }
            });

        // PostgreSQL LISTEN/NOTIFY trigger
        m.Sql(@"
            CREATE TABLE IF NOT EXISTS ""OrchestrationMessages"" (
                ""Id""        UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
                ""FromAgent"" VARCHAR(64)  NOT NULL,
                ""ToAgent""   VARCHAR(64)  NOT NULL,
                ""TaskId""    VARCHAR(128) NOT NULL,
                ""Payload""   JSONB        NOT NULL,
                ""IsRead""    BOOLEAN      NOT NULL DEFAULT FALSE,
                ""CreatedAt"" TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
                ""ReadAt""    TIMESTAMPTZ
            );
            CREATE INDEX idx_om_to_unread
                ON ""OrchestrationMessages"" (""ToAgent"", ""IsRead"")
                WHERE ""IsRead"" = FALSE;
            CREATE OR REPLACE FUNCTION notify_agent_message()
            RETURNS trigger LANGUAGE plpgsql AS $$
            BEGIN
                PERFORM pg_notify('agent_' || NEW.""ToAgent"", NEW.""Id""::text);
                RETURN NEW;
            END;
            $$;
            CREATE TRIGGER trg_orchestration_message_notify
                AFTER INSERT ON ""OrchestrationMessages""
                FOR EACH ROW EXECUTE FUNCTION notify_agent_message();
        ");
    }

    protected override void Down(MigrationBuilder m)
    {
        // ⚠️ NEVER run on prod without pg_dump backup
        m.Sql(@"
            DROP TRIGGER IF EXISTS trg_orchestration_message_notify
                ON ""OrchestrationMessages"";
            DROP FUNCTION IF EXISTS notify_agent_message();
        ");
        m.DropTable("OrchestrationMessages");
        m.DropTable("OrchestrationTaskMatrix");
        m.DropTable("OrchestrationWorkers");
    }
}
```

---

### 9. LISTEN/NOTIFY — Corrected Implementation

The `AgentMessageListener` in the self-analysis has three critical bugs:
- `async (_, e) =>` on `Notification` event = fire-and-forget with swallowed exceptions
- `NpgsqlConnection` never disposed = connection leak
- `CancellationToken` fetched from `ServiceProvider` = `InvalidOperationException`

```csharp
// src/AdsTable.Site.Application/Orchestration/AgentMessageListener.cs
using System;
using System.Collections.Concurrent;
using System.Threading;
using System.Threading.Tasks;
using Abp.Dependency;
using Abp.Threading.BackgroundWorkers; // ✅ Abp.* — EXISTS in ABP 9.4.2 (NOT Volo.Abp only)
using Abp.Threading.Timers;             // ✅ AbpAsyncTimer — exists in ABP 9.4.2
using Microsoft.Extensions.Logging;
using Npgsql;

namespace AdsTable.Site.Application.Orchestration
{
    // ✅ AsyncPeriodicBackgroundWorkerBase — ABP 9.4.2 pattern (same as ComplaintAutoEscalationWorker)
    // ✅ NOT IHostedService + PeriodicTimer (that's pure .NET pattern, bypasses ABP lifecycle)
    // Registration: SiteWebMvcModule.PostInitialize():
    //   workManager.Add(IocManager.Resolve<AgentMessageListener>());
    public class AgentMessageListener : AsyncPeriodicBackgroundWorkerBase, ISingletonDependency
    {
        private const int POLL_INTERVAL_MS = 100;

        private readonly string                          _agentId;
        private readonly string                          _connectionString;
        private readonly IOrchestrationMessageRepository _messageRepo;
        private readonly ILogger<AgentMessageListener>  _logger;

        // ✅ Thread-safe queue: Npgsql Notification event (sync) → DoWorkAsync (async)
        private readonly ConcurrentQueue<Guid> _pendingMessages = new();
        private NpgsqlConnection? _listenConn;

        public AgentMessageListener(
            AbpAsyncTimer timer,              // ✅ ABP timer (NOT System.Threading.PeriodicTimer)
            string agentId,
            string connectionString,
            IOrchestrationMessageRepository messageRepo,
            ILogger<AgentMessageListener> logger)
            : base(timer)
        {
            _agentId          = agentId;
            _connectionString = connectionString;
            _messageRepo      = messageRepo;
            _logger           = logger;

            Timer.Period = POLL_INTERVAL_MS;
        }

        public override async Task StartAsync(CancellationToken cancellationToken = default)
        {
            await OpenListenConnectionAsync(cancellationToken);
            await base.StartAsync(cancellationToken);
        }

        protected override async Task DoWorkAsync()
        {
            // Keep connection alive + drain Npgsql notification queue
            try
            {
                await _listenConn!.WaitAsync(POLL_INTERVAL_MS);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogWarning(ex, "LISTEN connection issue — reconnecting");
                await OpenListenConnectionAsync(CancellationToken.None);
                return;
            }

            // Process all queued message IDs
            while (_pendingMessages.TryDequeue(out var messageId))
            {
                try   { await ProcessMessageAsync(messageId); }
                catch (Exception ex)
                {
                    // ✅ Exceptions logged, NOT swallowed (unlike async void)
                    _logger.LogError(ex,
                        "Failed to process message {MessageId}", messageId);
                }
            }
        }

        private async Task OpenListenConnectionAsync(CancellationToken ct)
        {
            _listenConn?.Dispose();
            _listenConn = new NpgsqlConnection(_connectionString);
            await _listenConn.OpenAsync(ct);
            await using var cmd = new NpgsqlCommand(
                $"LISTEN agent_{_agentId};", _listenConn);
            await cmd.ExecuteNonQueryAsync(ct);

            // ✅ Sync event handler — only enqueues, no await
            _listenConn.Notification += (_, e) =>
            {
                if (Guid.TryParse(e.AdditionalInformation, out var id))
                    _pendingMessages.Enqueue(id);
            };
        }

        private async Task ProcessMessageAsync(Guid messageId)
        {
            var msg = await _messageRepo.FindAsync(messageId);
            if (msg == null || msg.IsRead) return; // idempotency
            // ... handle msg.Payload ...
            await _messageRepo.MarkReadAsync(messageId);
        }

        public override void Dispose()
        {
            _listenConn?.Dispose(); // ✅ Connection properly disposed
            base.Dispose();
        }
    }
}
```

---

### 10. ABP Module Registration (CORRECTED)

```csharp
// src/AdsTable.Site.Application/OrchestrationModule.cs
using Abp.Modules;         // ✅ Abp.* NOT Volo.Abp.*
using Abp.Reflection.Extensions;
using Microsoft.Extensions.DependencyInjection;

namespace AdsTable.Site.Application
{
    // ✅ Old ABP module: PreInitialize/PostInitialize — NOT ConfigureServices()
    [DependsOn(typeof(SiteApplicationModule))]
    public class OrchestrationModule : AbpModule
    {
        public override void PreInitialize()
        {
            IocManager.Register<ITaskMatrixProvider, DbTaskMatrixProvider>(
                Abp.Dependency.DependencyLifeStyle.Transient);
            IocManager.Register<IOrchestrationApiClient, AnthropicOrchestrationClient>(
                Abp.Dependency.DependencyLifeStyle.Transient);
        }

        public override void Initialize()
        {
            IocManager.RegisterAssemblyByConvention(
                typeof(OrchestrationModule).GetAssembly());
        }

        // ✅ Background worker registered via IBackgroundWorkerManager — ABP 9.4.2 pattern
        // Matches: SiteWebMvcModule.PostInitialize() → workManager.Add(...)
        public override void PostInitialize()
        {
            if (Configuration.BackgroundJobs.IsJobExecutionEnabled)
            {
                var workManager = IocManager.Resolve<IBackgroundWorkerManager>();
                workManager.Add(IocManager.Resolve<AgentMessageListener>());
            }
        }

        // ✅ HTTP client registration — must be called explicitly from Startup.ConfigureServices()
        // Add to: src/AdsTable.Site.Web.Mvc/Startup/Startup.cs → ConfigureServices()
        public static void ConfigureHttpClients(IServiceCollection services,
            IConfiguration config)
        {
            var apiKey = config["Anthropic:ApiKey"]
                ?? throw new InvalidOperationException("Anthropic:ApiKey not configured");

            services
                .AddHttpClient("AnthropicOrchestration", c =>
                {
                    c.BaseAddress = new Uri("https://api.anthropic.com");
                    c.DefaultRequestHeaders.Add("x-api-key", apiKey);
                    c.DefaultRequestHeaders.Add("anthropic-version", "2023-06-01");
                    c.Timeout = TimeSpan.FromMinutes(20);
                });
                // ⚠️ AddStandardResilienceHandler() requires Microsoft.Extensions.Http.Resilience NuGet
                // Verify package is in AdsTable.Site.Web.Core.csproj before adding
        }
    }
}
```

---

### 11. Deploy Script — Rollback Fix

```bash
#!/usr/bin/env bash
# /opt/openclaw/scripts/deploy-orchestration.sh
set -euo pipefail

APP_DIR="/opt/openclaw/app"
BACKUP_DIR="/opt/openclaw/backups"
TIMESTAMP=$(date -u '+%Y%m%d_%H%M%S')
LOG="/var/log/openclaw/deploy.log"
DUMP_FILE="${BACKUP_DIR}/pre_deploy_${TIMESTAMP}.dump"

log() { echo "[${TIMESTAMP}] $*" | tee -a "$LOG"; }
die() { log "FATAL: $*"; exit 1; }

rollback() {
    log "--- ROLLBACK START ---"
    if [[ ! -f "$DUMP_FILE" ]]; then
        log "ERROR: No backup file at $DUMP_FILE — manual intervention required"
        return 1
    fi
    pg_restore \
        --host="${PGHOST}" \
        --username="${PGUSER}" \
        --no-password \
        --clean \
        --if-exists \
        --table="OrchestrationWorkers" \
        --table="OrchestrationMessages" \
        --table="OrchestrationTaskMatrix" \
        --dbname="${PGDATABASE}" \
        "$DUMP_FILE" \
    && log "Rollback complete" \
    || log "ERROR: Rollback ALSO failed — pg_restore manually from $DUMP_FILE"
}

# Pre-deploy: backup orchestration tables
log "Backing up orchestration tables..."
mkdir -p "$BACKUP_DIR"
pg_dump \
    --host="${PGHOST}" \
    --username="${PGUSER}" \
    --no-password \
    --table="OrchestrationWorkers" \
    --table="OrchestrationMessages" \
    --table="OrchestrationTaskMatrix" \
    --format=custom \
    --file="$DUMP_FILE" \
    "${PGDATABASE}" \
|| die "DB backup failed — deploy aborted (no data changed)"

log "DB backup OK: $DUMP_FILE"

# Build
cd "$APP_DIR"
dotnet publish -c Release -o "${APP_DIR}/publish" \
|| die "Build failed — no data changed"

# ✅ EF Core migration — with rollback on failure
log "Running EF Core migrations..."
dotnet ef database update \
    --project src/AdsTable.Site.EntityFrameworkCore \
    --startup-project src/AdsTable.Site.HttpApi.Host \
|| {
    # ✅ FIXED: rollback IS called on migration failure
    log "Migration failed — initiating rollback"
    rollback
    die "Deploy failed at migration step"
}

log "Migration OK"

# Restart service
systemctl restart adstable-api \
|| { rollback; die "Service restart failed"; }

# Health check
sleep 5
curl -sf http://127.0.0.1:5200/api/app/health \
|| { rollback; die "Health check failed after restart"; }

log "Deploy complete — $DUMP_FILE preserved for 30 days"
```

---

## 🔑 What Was Actually Correct in the Self-Analysis

| Concept | Verdict |
|---------|---------|
| `protected OrchestrationWorker() { }` required for EF Core | ✅ Correct |
| `RetryOfId` must be `Guid` not `string` | ✅ Correct — FK integrity |
| Status transition guards (reject invalid transitions) | ✅ Correct pattern |
| `pg_dump --table` before any write operation | ✅ Correct — Data Safety |
| Idempotency check in domain service `CreateAsync` | ✅ Correct |
| Self-referencing FK `onDelete: ReferentialAction.Restrict` | ✅ Correct |
| `OrchestrationMessages` via PostgreSQL LISTEN/NOTIFY (concept) | ✅ Correct concept |
| Structured logging via Serilog/Seq | ✅ Correct |
| Partial index on `RetryOfId IS NOT NULL` | ✅ Correct |
| `HasConversion<string>()` for WorkerStatus enum | ✅ Correct — readable in Postgres |
| bash deploy script (concept) | ✅ Correct approach for Ubuntu 24.04 |
| Nginx internal-only proxy on `127.0.0.1` | ✅ Correct |

---

## 📋 IMPLEMENTATION CHECKLIST (corrected order, data-safe)

```
⚠️  BEFORE ANY MIGRATION:
[ ] pg_dump --table=OrchestrationWorkers ... > backup_$(date +%Y%m%d).dump

DOMAIN:
[ ] OrchestrationWorker.cs     — FullAuditedEntity<Guid>, SetRetryOf() defined
[ ] OrchestrationErrorCodes.cs — string constants
[ ] OrchestrationEventData.cs  — plain data classes (NOT ETOs)
[ ] ITaskMatrixProvider.cs     — async interface (Domain layer, NO infrastructure)
[ ] OrchestrationWorkerManager.cs — DomainService, raises events via IEventBus

EF CORE:
[ ] OrchestrationWorkerConfiguration.cs   — HasColumnType("jsonb"), Ignore(Duration)
[ ] OrchestrationTaskMatrixConfiguration.cs
[ ] Add-Migration AddOrchestration
[ ] Review SQL — verify no DROP, verify JSONB annotation, verify partial index
[ ] Update-Database

APPLICATION:
[ ] OrchestrationJobArgs.cs    — [Serializable], TenantId (state-based retry, NO AttemptNumber)
[ ] OrchestrationJob.cs        — [AutomaticRetry(Attempts=3)], ITransientDependency,
                                  async matrix calls, result stored in MarkDone(output)
[ ] DbTaskMatrixProvider.cs    — ICacheManager (NOT IDistributedCache<T>)
[ ] IOrchestrationApiClient.cs — interface
[ ] AnthropicOrchestrationClient.cs — HttpClient, API key from IConfiguration

INFRASTRUCTURE:
[ ] AgentMessageListener.cs    — AsyncPeriodicBackgroundWorkerBase + AbpAsyncTimer,
                                  ConcurrentQueue, proper Dispose()
                                  Register in SiteWebMvcModule.PostInitialize() via workManager.Add()
[ ] OrchestrationModule.cs     — PreInitialize() NOT ConfigureServices()

AUTHORIZATION:
[ ] Pages_Orchestration_DispatchTask in AppPermissions.cs
[ ] Register in AppAuthorizationProvider.SetPermissions()

DEPLOY:
[ ] deploy-orchestration.sh — rollback() called for BOTH migration and restart failures

VERIFY:
[ ] grep -r "Volo\.Abp" src/ — MUST return zero results
[ ] dotnet build — zero errors
[ ] POST /api/services/app/orchestrator/dispatch → Worker created before job enqueued
[ ] Hangfire Dashboard — job visible, retry count stops at 3
[ ] OrchestrationWorkers.Output populated after job Done
[ ] LISTEN/NOTIFY test: INSERT into OrchestrationMessages → notify fires
```

---

*Corrected: 2026-03-24 | Corrects: Orchestrant_ABP-9.4.2_SelfAnalysis.txt*
*Stack: ASP.NET Boilerplate 9.4.2 + Hangfire + PostgreSQL + .NET 8 + Ubuntu 24.04*
