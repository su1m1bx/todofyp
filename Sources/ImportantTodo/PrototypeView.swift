import SwiftUI

struct PrototypeView: View {
    var hide: () -> Void
    @State private var input = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("최상위 창 프로토타입").font(.headline)
            Text("일반 앱·Spaces·전체 화면·Stage Manager에서 이 창이 보이는지, 다른 앱 입력을 빼앗지 않는지 확인하세요.")
            TextField("클릭 후 한글·영문 입력 확인", text: $input)
            Button("숨기기", action: hide)
            Text("메뉴 막대 아이콘: 표시/숨기기\n보조 클릭: 투두 보기·설정·종료\n아이콘이 보이지 않으면 Finder에서 앱을 다시 실행하세요.")
                .font(.callout)
            Text("표시 호환성은 아직 검증되지 않았습니다.").foregroundStyle(.secondary)
            Spacer()
        }.padding()
    }
}
