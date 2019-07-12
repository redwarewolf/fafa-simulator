using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.SceneManagement;

public class GameMaster : MonoBehaviour
{
  static public Player player;
  static public Club enemyClub;

  void Awake(){
    if (player == null){
      player = new Player();
    }
  }

  public void finishMatch(){
    Debug.Log(player.getCash());
    player.addCash(500);
    Debug.Log(player.getCash());
    SceneManager.LoadScene("MainScene");
  }

  public void loadNextMatch(){
    SceneManager.LoadScene("MatchScene");
  }

  public Player getPlayer(){
    return player;
  }

  public int getPlayerCash(){
    return player.getCash();
  }

  public Club getEnemyClub(){
    return enemyClub;
  }
}
