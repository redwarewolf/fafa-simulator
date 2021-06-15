using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using System.Linq;

public class Club : MonoBehaviour
{
    
    public string name { get; set; }
    public string division { get; set; }
    public FootballPlayer goalkeeper { get; set; }
    public List<FootballPlayer> defense { get; set; }
    public List<FootballPlayer> midfielders { get; set; }
    public List<FootballPlayer> attack { get; set; }

    public Club(string _name,
                FootballPlayer _gk,
                List<FootballPlayer> _defenders,
                List<FootballPlayer> _midfield,
                List<FootballPlayer> _attackers){
        name = _name;
        goalkeeper = _gk;
        defense = _defenders;
        midfielders = _midfield;
        attack = _attackers;
    }

    public int defending(){
        return defense.Select(x => x.defSkill).Sum();
    }

    public int midfield(){
        return midfielders.Select(x => x.midSkill).Sum();
    }

    public int attacking(){
        return attack.Select(x => x.atkSkill).Sum();
    }

    public int goalkeeping(){
        return goalkeeper.gkSkill;
    }

    public string getName(){
        return name;
    }
}
