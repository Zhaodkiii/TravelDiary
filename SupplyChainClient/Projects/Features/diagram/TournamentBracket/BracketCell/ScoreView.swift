//
//  ScoreView.swift
//  Brackets
//
//  Created by Manikandan on 21/08/24.
//

import SwiftUI

struct ScoreView: View {
    
    var team : Team?
    @EnvironmentObject var theme : TournamentBracketTheme
    
    var body: some View {
        HStack{

            if let _team = team{
                if let _imageView = _team.image{
                    Image(uiImage: _imageView)
                        .resizable()
                        .frame(width: 20,height: 20)
                        .cornerRadiusStyle(2)
                }
                
                Text(_team.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(_team.points)")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }else{
                Image(systemName: "")
                    .resizable()
                    .frame(width: 20,height: 20)
                    .cornerRadiusStyle(2)

                Text("TBD")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.vertical,5)
            }
        }

    }
}

#Preview {
    ScoreView(team: Team(id: 1, name: "India", image: UIImage(named: "India"), points: 3))
        .environmentObject(TournamentBracketTheme(fontColor: "123232"))
    
}
