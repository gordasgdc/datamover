import SwiftUI

/// Ghid de utilizare pas cu pas — fereastra deschisa din meniul Help.
struct HelpView: View {
    private let steps: [(String, String)] = [
        ("1. Adauga surse", "Trage fisiere sau foldere din Finder in coloana SOURCES (stanga), sau apasa in zona punctata pentru a alege manual."),
        ("2. Alege discul sau folderul de destinatie", "In coloana centrala Disks apar discurile montate — trage un disc peste coloana DESTINATIONS (dreapta). Poti trage si un folder direct din Finder peste DESTINATIONS, ca sa salvezi exact in acel folder, nu neaparat pe radacina unui disc."),
        ("3. Denumeste proiectul/cardul (optional)", "Completeaza campurile Proiect si Card de sus — folderul creat la destinatie va avea numele \"AAAA-LL-ZZ_Proiect_Card\". Daca le lasi goale, se folosesc \"Proiect\"/\"Card\"."),
        ("4. Setari de copiere", "Apasa pe iconita rotii dintate din dreapta jos pentru a alege modelul de verificare (MD5/SHA1/SHA256/SHA512/doar marime), pentru a adauga excluderi (nume sau extensii separate prin virgula) si pentru a activa reluarea automata dintr-un checkpoint existent."),
        ("5. Start", "Apasa Start. Bara de progres si viteza de transfer apar in partea de jos. Poti apasa Anuleaza oricand — la o reluare ulterioara, fisierele deja copiate si verificate sunt sarite automat daca ai lasat activata reluarea."),
        ("6. Raport", "La final se scrie un raport CSV si un raport PDF in folderul de destinatie, cu starea fiecarui fisier (OK/sarit/eroare). Le poti deschide direct din Finder cu linkul din meniul de setari."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Ghid de utilizare DataMover").font(.title2).bold()
                ForEach(steps, id: \.0) { step in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.0).font(.system(size: 13, weight: .semibold))
                        Text(step.1).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 480, height: 460)
    }
}
