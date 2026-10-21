import Foundation
import SwiftData

/// 创建持久化容器。模型类型保持内部可见，App 通过这里创建容器。
public enum VigorStoreFactory {
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(
            for: CycleRecord.self, JournalRecord.self, ConfigRecord.self,
            SleepOverrideRecord.self, ManualExclusionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
        )
    }
}
